import AppKit
import FlowCore
import IOKit.hid
import Observation
import os
import ServiceManagement

let log = Logger(subsystem: "com.barathwaj.mousedriver", category: "app")

@MainActor @Observable
final class AppModel {
    // MARK: Config & engine

    var config: Config {
        didSet {
            guard config != oldValue else { return }
            engine.config = config
            do { try store.save(config) } catch { lastError = "Couldn't save settings: \(error.localizedDescription)" }
        }
    }

    @ObservationIgnored let store = ConfigStore()
    @ObservationIgnored let engine: MappingEngine
    @ObservationIgnored private let watcher = DeviceMonitor()
    @ObservationIgnored private var permissionTimer: Timer?

    var engineRunning = false
    var lastError: String?
    var lastAction: String?

    // MARK: Devices

    var transports: [Transport] = []
    var bluetoothBattery: Int?
    @ObservationIgnored private let btBattery = BluetoothBattery()

    /// Battery from the dongle's status report, else from the BLE Battery Service.
    var batteryPercent: Int? {
        hardwareStatus.map { Int($0.batteryPercent) } ?? bluetoothBattery
    }
    var connectionSummary: String {
        transports.isEmpty ? "Not connected" : transports.map(\.rawValue).joined(separator: " + ")
    }

    // MARK: Permissions

    var accessibilityGranted = AXIsProcessTrusted()
    var inputMonitoringGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    var permissionsGranted: Bool { accessibilityGranted && inputMonitoringGranted }

    // MARK: Button capture ("press a button on your mouse")

    var isCapturing = false
    @ObservationIgnored private var captureHandler: ((Int) -> Void)?

    // MARK: Hardware (dongle / cable)

    /// Onboard writes haven't been tested on a real dongle yet, so the Hardware tab is opt-in:
    /// `defaults write com.barathwaj.mousedriver experimentalHardware -bool true`
    @ObservationIgnored let hardwareEnabled = UserDefaults.standard.bool(forKey: "experimentalHardware")
    var hardware: HardwareController?
    var hardwareStatus: DeviceStatus?
    var hardwarePrefs = HardwarePrefs.load() { didSet { hardwarePrefs.save() } }
    var hardwareBusy = false
    var hardwareMessage: String?

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Launch at login: \(error.localizedDescription)"
            }
        }
    }

    init() {
        let store = ConfigStore()
        let loaded: Config
        var loadError: String?
        do { loaded = try store.load() } catch {
            loaded = .default
            loadError = "Couldn't read \(store.url.path) (\(error.localizedDescription)). Using defaults; your file is left untouched until you change a setting."
        }
        config = loaded
        engine = MappingEngine(config: loaded)
        lastError = loadError

        engine.onRawInput = { [weak self] event in
            guard let self, event.isButton, event.value != 0, let handler = self.captureHandler else { return }
            self.captureHandler = nil
            self.isCapturing = false
            handler(event.usage)
        }
        engine.onAction = { [weak self] button, action in
            self?.lastAction = "Button \(button) → \(action.displayName)"
            log.notice("button \(button) → \(action.displayName, privacy: .public)")
        }
        engine.onButtonPress = { button in
            log.notice("HID button \(button) pressed")
        }

        btBattery.onLevel = { [weak self] level in self?.bluetoothBattery = level }
        watcher.onChange = { [weak self] in self?.devicesChanged() }
        watcher.start(readInput: false)

        startEngineWhenPermitted()
    }

    // MARK: Engine lifecycle

    func startEngineWhenPermitted() {
        refreshPermissions()
        tryStartEngine()
        guard !engineRunning, permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshPermissions()
                self.tryStartEngine()
                if self.engineRunning {
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                }
            }
        }
    }

    private func tryStartEngine() {
        guard !engineRunning, permissionsGranted else { return }
        do {
            try engine.start()
            engineRunning = true
            lastError = nil
            log.notice("engine started; devices: \(self.connectionSummary, privacy: .public)")
        } catch {
            engineRunning = false
            log.error("engine failed to start: \(String(describing: error), privacy: .public)")
        }
    }

    func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacyPane("Privacy_Accessibility")
    }

    func requestInputMonitoring() {
        if !IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
            openPrivacyPane("Privacy_ListenEvent")
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Drops our entry for a TCC service ("Accessibility", "ListenEvent"), which
    /// clears grants left over from an older build with a different signature.
    func resetPermission(_ service: String) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleID]
        do {
            try process.run()
            process.waitUntilExit()
            lastError = process.terminationStatus == 0
                ? nil
                : "tccutil reset \(service) failed (status \(process.terminationStatus))"
        } catch {
            lastError = "Couldn't run tccutil: \(error.localizedDescription)"
        }
        refreshPermissions()
    }

    /// Input Monitoring only applies to a process started after the grant.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        engine.stop()
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    log.error("relaunch failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: Capture

    func captureButton(_ handler: @escaping (Int) -> Void) {
        captureHandler = handler
        isCapturing = true
    }

    func cancelCapture() {
        captureHandler = nil
        isCapturing = false
    }

    // MARK: Devices & hardware

    private func devicesChanged() {
        transports = watcher.transports
        log.notice("devices: \(self.connectionSummary, privacy: .public)")
        if transports.contains(.bluetooth) { btBattery.start() } else { bluetoothBattery = nil }
        if hardwareEnabled, let iface = watcher.configInterface {
            guard hardware?.interface != iface else { return }
            let controller = HardwareController(interface: iface)
            controller.onStatus = { [weak self] status in self?.hardwareStatus = status }
            hardware = controller
            Task { await controller.refreshStatus() }
        } else {
            hardware?.close()
            hardware = nil
            hardwareStatus = nil
        }
    }

    /// Runs a hardware command, tracking busy state and reporting the result.
    func runHardware(_ label: String, _ body: @escaping (HardwareController) async throws -> Void) {
        guard let hardware, !hardwareBusy else { return }
        hardwareBusy = true
        hardwareMessage = "\(label)…"
        Task {
            do {
                try await body(hardware)
                hardwareMessage = "\(label): done"
                await hardware.refreshStatus()
            } catch {
                hardwareMessage = "\(label) failed: \(error)"
            }
            hardwareBusy = false
        }
    }

    // MARK: Profile editing helpers

    func binding(profile index: Int, button: Int) -> Action? {
        config.profiles[index].bindings.first { $0.button == button }?.action
    }

    func setBinding(profile index: Int, button: Int, action: Action?) {
        var bindings = config.profiles[index].bindings.filter { $0.button != button }
        if let action { bindings.append(ButtonBinding(button: button, action: action)) }
        config.profiles[index].bindings = bindings.sorted { $0.button < $1.button }
    }
}
