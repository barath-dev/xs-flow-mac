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

    /// Connected external mice.
    var mice: [PointingDevice] = []
    /// Bluetooth battery levels by peripheral name.
    var bluetoothBattery: [String: Int] = [:]
    @ObservationIgnored private let btBattery = BluetoothBattery()

    /// Battery from the XS Flow dongle's status report, else from the BLE Battery Service.
    func battery(for mouse: PointingDevice) -> Int? {
        if mouse.isXSFlow, !mouse.isBluetooth, let status = hardwareStatus { return Int(status.batteryPercent) }
        return BluetoothBattery.level(in: bluetoothBattery, forDeviceNamed: mouse.name)
    }
    var connectionSummary: String {
        mice.isEmpty ? "No mouse connected" : mice.map { "\($0.name) (\($0.transportLabel))" }.joined(separator: ", ")
    }

    func isCustomized(_ mouse: PointingDevice) -> Bool { config.manages(mouse) }

    func setCustomized(_ model: DeviceID, _ on: Bool) {
        config.excludedDevices.removeAll { $0 == model }
        if !on { config.excludedDevices.append(model) }
    }

    // MARK: Permissions

    var accessibilityGranted = AXIsProcessTrusted()
    var inputMonitoringGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    var permissionsGranted: Bool { accessibilityGranted && inputMonitoringGranted }

    // MARK: Button capture ("press a button on your mouse")

    var isCapturing = false

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

        engine.onAction = { [weak self] button, action in
            self?.lastAction = "Button \(button) → \(action.displayName)"
            log.notice("button \(button) → \(action.displayName, privacy: .public)")
        }
        engine.onButtonPress = { button, device in
            log.notice("HID button \(button) pressed on \(device.name, privacy: .public)")
        }

        btBattery.onChange = { [weak self] in
            guard let self else { return }
            self.bluetoothBattery = self.btBattery.levels
        }
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
        isCapturing = true
        engine.captureNextButton { [weak self] button in
            self?.isCapturing = false
            handler(button)
        }
    }

    func cancelCapture() {
        engine.cancelCapture()
        isCapturing = false
    }

    // MARK: Devices & hardware

    private func devicesChanged() {
        refreshMice()
        // The HID event system can register a new mouse a moment after IOHIDManager reports it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refreshMice() }
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

    private func refreshMice() {
        engine.registry.invalidate()
        let current = engine.registry.mice()
        guard current != mice else { return }
        mice = current
        log.notice("mice: \(self.connectionSummary, privacy: .public)")
        btBattery.track(names: mice.filter(\.isBluetooth).map(\.name))
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
