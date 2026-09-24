import Foundation
import FlowCore

let usage = """
flowctl — XS Flow mouse probe & configuration tool

USAGE:
  flowctl list                 List connected XS Flow HID interfaces
  flowctl monitor              Print raw HID input from the mouse (Ctrl+C to stop)
  flowctl run [--config PATH]  Run the remapping engine headless with a config file
  flowctl example-config       Print an example config (JSON)
  flowctl pointer              Show the mouse's current per-device tracking speed
  flowctl battery              Read the battery level over Bluetooth LE

HARDWARE (needs the 2.4G dongle or USB cable; settings are saved on the mouse).
EXPERIMENTAL: untested on real hardware, so every command needs --experimental.
  flowctl hw status                      Battery, DPI level, polling rate, sensor
  flowctl hw rate <125|250|500|1000|…>   Set polling rate
  flowctl hw dpi <400,800,1600,…> [--level N]   Set DPI levels (up to 8) and active level (0-based)
  flowctl hw light <mode> [--speed 1-3] [--brightness 1-4]
                                         Modes: off, rainbowFlow, breathe, steady, neon, marquee, rainbowSteady, wave
  flowctl hw button <slot> <function>    Remap an onboard button (flowctl hw button list for names)
  flowctl hw sleep <1-15>                Idle minutes before the mouse sleeps
  flowctl hw reset                       Factory-reset the mouse's onboard settings
  Add --trace to any hw command to print raw packets.

Default config: ~/Library/Application Support/MouseDriver/config.json
"""

func withMonitor(readInput: Bool = true, _ body: @escaping (DeviceMonitor) -> Void) -> Never {
    let monitor = DeviceMonitor()
    let status = monitor.start(readInput: readInput)
    if status != kIOReturnSuccess {
        fputs(String(format: "IOHIDManagerOpen failed: 0x%08X\n", status), stderr)
        if status == kIOReturnNotPermitted {
            fputs("Grant Input Monitoring to your terminal in System Settings → Privacy & Security.\n", stderr)
        }
        exit(1)
    }
    // Matching callbacks fire on the first run loop pass.
    DispatchQueue.main.async { body(monitor) }
    RunLoop.main.run()
    exit(0)
}

func hex(_ n: Int, _ width: Int = 4) -> String { String(format: "0x%0\(width)X", n) }

func list(_ monitor: DeviceMonitor) {
    if monitor.interfaces.isEmpty {
        print("No XS Flow mouse found (Bluetooth 32C2:6621 or dongle/cable 04F3:026F/026E).")
        exit(1)
    }
    for iface in monitor.interfaces.sorted(by: { $0.primaryUsagePage < $1.primaryUsagePage }) {
        let features = ReportDescriptor.featureReportIDs(in: iface.reportDescriptor).sorted()
        print("""
        \(iface.product)  [\(iface.known.transport.rawValue), \(iface.transportName)]
          VID:PID       \(hex(iface.known.vendorID)):\(hex(iface.known.productID))
          usage         page \(hex(iface.primaryUsagePage, 2)) usage \(hex(iface.primaryUsage, 2))
          feature IDs   \(features.isEmpty ? "none" : features.map(String.init).joined(separator: ", "))
          config iface  \(iface.isConfigInterface ? "yes" : "no")
        """)
    }
    exit(0)
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "list":
    withMonitor(readInput: false, list)
case "monitor":
    withMonitor { monitor in
        print("Listening to \(monitor.transports.map(\.rawValue).joined(separator: ", ")). Press buttons / scroll…")
        monitor.onInput = { event in
            // Pointer motion is noisy; only show it when asked.
            if !args.contains("--motion"),
               event.usagePage == 0x01, event.usage == 0x30 || event.usage == 0x31 { return }
            print("[\(event.transport.rawValue)] \(event.description)")
        }
        monitor.onChange = { print("devices: \(monitor.transports.map(\.rawValue))") }
    }
case "run":
    let path = args.firstIndex(of: "--config").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
    let store = path.map { ConfigStore(url: URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)) } ?? ConfigStore()
    let config: Config
    do { config = try store.load() } catch {
        fputs("Could not read \(store.url.path): \(error)\n", stderr)
        exit(1)
    }
    let engine = MappingEngine(config: config)
    engine.onAction = { button, action in print("button \(button) → \(action.displayName)") }
    engine.onDevicesChanged = { print("devices: \(engine.monitor.transports.map(\.rawValue))") }
    do { try engine.start() } catch MappingEngine.StartError.inputMonitoringDenied {
        fputs("Input Monitoring permission needed for this terminal (System Settings → Privacy & Security).\n", stderr)
        exit(1)
    } catch {
        fputs("Accessibility permission needed for this terminal (System Settings → Privacy & Security).\n", stderr)
        exit(1)
    }
    signal(SIGINT, SIG_IGN)
    let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigint.setEventHandler { engine.stop(); exit(0) }
    sigint.resume()
    print("Engine running with \(store.url.path) (\(config.profiles.count) profile(s)). Ctrl+C to stop.")
    RunLoop.main.run()
case "example-config":
    let example = Config(
        scroll: ScrollSettings(reverseVertical: true, speed: 1.5),
        pointer: PointerSettings(trackingSpeed: 2.0),
        profiles: [
            Profile(name: "Default", bindings: [
                ButtonBinding(button: 3, action: .system(action: .missionControl)),
                ButtonBinding(button: 4, action: .shortcut(combo: KeyCodes.parseCombo("cmd+[")!)),
                ButtonBinding(button: 5, action: .shortcut(combo: KeyCodes.parseCombo("cmd+]")!)),
            ]),
            Profile(name: "Music", bundleIDs: ["com.apple.Music", "com.spotify.client"], bindings: [
                ButtonBinding(button: 4, action: .media(key: .previous)),
                ButtonBinding(button: 5, action: .media(key: .next)),
            ]),
        ]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(data: try! encoder.encode(example), encoding: .utf8)!)
case "pointer":
    let applier = PointerApplier()
    if let speed = applier.currentTrackingSpeed {
        print(String(format: "Tracking speed (this mouse): %.2f", speed))
    } else {
        print("Mouse not found.")
    }
case "battery":
    let battery = BluetoothBattery()
    battery.onLevel = { level in
        print(level.map { "Battery: \($0)%" } ?? "No Bluetooth XS Flow with a battery service found.")
        exit(level == nil ? 1 : 0)
    }
    battery.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
        fputs("Timed out. Is Bluetooth permission granted to this terminal?\n", stderr)
        exit(1)
    }
    RunLoop.main.run()
case "hw":
    runHardware(Array(args.dropFirst()))
default:
    print(usage)
    exit(args.isEmpty ? 0 : 1)
}

// MARK: - Hardware commands

func option(_ args: [String], _ name: String) -> String? {
    args.firstIndex(of: name).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
}

func fail(_ message: String) -> Never {
    fputs(message + "\n", stderr)
    exit(1)
}

func printStatus(_ status: DeviceStatus) {
    print("""
    battery       \(status.batteryPercent)%\(status.isCharging ? " (charging)" : "")
    DPI level     \(status.dpiLevel)
    polling rate  \(status.pollingRate.map { "\($0.hertz) Hz" } ?? "code \(status.reportRate)")
    max rate      \(PollingRate.supported(maxReportRate: status.maxReportRate).map(\.hertz).max() ?? 0) Hz
    lighting      \(LightingMode(rawValue: status.lightingMode)?.displayName ?? "mode \(status.lightingMode)")
    sensor        \(status.sensorName)
    link          \(status.linkStatus)
    """)
}

func runHardware(_ args: [String]) {
    let slotNames = OnboardButton.allCases.map { ($0, $0.displayName.lowercased().replacingOccurrences(of: " ", with: "")) }
    if args.first == "button", args.dropFirst().first == "list" {
        print("Slots:     " + OnboardButton.allCases.map { "\($0.rawValue)=\($0.displayName)" }.joined(separator: ", "))
        print("Functions: " + ButtonCode.presets.map(\.name).joined(separator: ", "))
        exit(0)
    }
    guard args.contains("--experimental") else {
        fail("Hardware commands haven't been tested on a real dongle yet. Add --experimental to run them anyway.")
    }

    withMonitor(readInput: false) { monitor in
        guard let iface = monitor.configInterface else {
            fail(monitor.interfaces.isEmpty
                 ? "No XS Flow found."
                 : "Only the Bluetooth connection is present. Hardware settings need the 2.4G dongle or USB cable.")
        }
        let hw = HardwareController(interface: iface)
        if args.contains("--trace") { hw.trace = { print("  \($0)") } }

        Task { @MainActor in
            do {
                // Get a status report first: DPI encoding depends on the sensor type.
                await hw.refreshStatus()
                try await Task.sleep(for: .milliseconds(300))

                switch args.first {
                case "status", nil:
                    guard let status = hw.status else { fail("The mouse didn't send a status report. Is it switched on?") }
                    printStatus(status)
                case "rate":
                    guard let hz = args.dropFirst().first.flatMap(Int.init), let rate = PollingRate(hertz: hz) else {
                        fail("Usage: flowctl hw rate <125|250|500|1000|2000|4000|8000>")
                    }
                    if let status = hw.status, !PollingRate.supported(maxReportRate: status.maxReportRate).contains(rate) {
                        fail("This mouse supports: \(PollingRate.supported(maxReportRate: status.maxReportRate).map(\.hertz))")
                    }
                    try await hw.setPollingRate(rate)
                    print("Polling rate set to \(hz) Hz.")
                case "dpi":
                    let levels = args.dropFirst().first?.split(separator: ",").compactMap { Int($0) } ?? []
                    guard !levels.isEmpty, levels.count <= 8, levels.allSatisfy({ (50...30000).contains($0) }) else {
                        fail("Usage: flowctl hw dpi 400,800,1600,3200 [--level 2]")
                    }
                    let level = option(args, "--level").flatMap(Int.init) ?? min(Int(hw.status?.dpiLevel ?? 0), levels.count - 1)
                    try await hw.setDPI(levels: levels, currentLevel: level)
                    var prefs = HardwarePrefs.load()
                    prefs.dpiLevels = levels
                    prefs.save()
                    print("DPI levels \(levels), active level \(level) (\(levels[level]) DPI).")
                case "light":
                    guard let name = args.dropFirst().first,
                          let mode = LightingMode.allCases.first(where: { "\($0)".lowercased() == name.lowercased() }) else {
                        fail("Usage: flowctl hw light <\(LightingMode.allCases.map { "\($0)" }.joined(separator: "|"))>")
                    }
                    try await hw.setLighting(
                        mode: mode,
                        brightness: option(args, "--brightness").flatMap(Int.init) ?? 4,
                        speed: option(args, "--speed").flatMap(Int.init) ?? 3
                    )
                    print("Lighting set to \(mode.displayName).")
                case "button":
                    let rest = Array(args.dropFirst())
                    guard rest.count >= 2 else { fail("Usage: flowctl hw button <slot> <function>  (see: flowctl hw button list)") }
                    let slotArg = rest[0].lowercased()
                    guard let slot = Int(slotArg).flatMap(OnboardButton.init(rawValue:))
                            ?? slotNames.first(where: { $0.1.hasPrefix(slotArg) })?.0 else { fail("Unknown slot \(rest[0]).") }
                    let fnName = rest[1...].prefix { !$0.hasPrefix("--") }.joined(separator: " ").lowercased()
                    guard let preset = ButtonCode.presets.first(where: { $0.name.lowercased() == fnName }) else {
                        fail("Unknown function \"\(fnName)\". See: flowctl hw button list")
                    }
                    // The mouse has no read-back for the map, so we rewrite all slots:
                    // the last map we wrote (or factory defaults) with this one change.
                    var prefs = HardwarePrefs.load()
                    prefs.buttons[slot.rawValue - 1] = preset.code
                    try await hw.setButtons(prefs.buttons)
                    prefs.save()
                    print("\(slot.displayName) → \(preset.name)")
                case "sleep":
                    guard let minutes = args.dropFirst().first.flatMap(Int.init), (1...15).contains(minutes) else {
                        fail("Usage: flowctl hw sleep <1-15>")
                    }
                    try await hw.setPower(sleepMinutes: minutes, moveWakeup: true, moveLighting: false)
                    print("Sleep after \(minutes) min idle.")
                case "reset":
                    try await hw.factoryReset()
                    HardwarePrefs().save()
                    print("Factory reset sent.")
                default:
                    fail(usage)
                }
                exit(0)
            } catch {
                fail("Error: \(error)")
            }
        }
    }
}
