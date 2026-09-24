import Foundation

/// A 3-byte onboard button function, as stored in the mouse's flash.
public struct ButtonCode: Codable, Hashable, Sendable {
    public var bytes: [UInt8]

    public init(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { bytes = [b0, b1, b2] }

    public static let leftClick = ButtonCode(0x10, 0x01, 0)
    public static let rightClick = ButtonCode(0x10, 0x02, 0)
    public static let middleClick = ButtonCode(0x10, 0x04, 0)
    public static let back = ButtonCode(0x10, 0x08, 0)
    public static let forward = ButtonCode(0x10, 0x10, 0)
    public static let wheelUp = ButtonCode(0x10, 0x20, 0)
    public static let wheelDown = ButtonCode(0x10, 0x40, 0)
    public static let dpiCycle = ButtonCode(0x40, 0x01, 0)
    public static let dpiUp = ButtonCode(0x40, 0x02, 0)
    public static let dpiDown = ButtonCode(0x40, 0x03, 0)
    public static let disabled = ButtonCode(0x60, 0x00, 0)
    public static let modeSwitch = ButtonCode(0x60, 0x01, 0)
    public static let lightingToggle = ButtonCode(0x60, 0x04, 0)
    public static let tiltLeft = ButtonCode(0x60, 0x06, 0)
    public static let tiltRight = ButtonCode(0x60, 0x07, 0)
    public static let showDesktop = ButtonCode(0x60, 0x08, 0)
    public static let unset = ButtonCode(0xFF, 0xFF, 0xFF)

    /// HID modifier bits: 0x01 Ctrl, 0x02 Shift, 0x04 Alt/Option, 0x08 GUI/Cmd. `usage` is a HID keyboard usage (a = 0x04).
    public static func key(modifiers: UInt8, usage: UInt8) -> ButtonCode { ButtonCode(0x70, modifiers, usage) }

    /// Consumer-page usage, e.g. 0xCD play/pause, 0xE9 volume up.
    public static func consumer(_ usage: UInt16) -> ButtonCode {
        ButtonCode(0x80, UInt8(usage & 0xFF), UInt8(usage >> 8))
    }

    public static let presets: [(name: String, code: ButtonCode)] = [
        ("Left Click", .leftClick), ("Right Click", .rightClick), ("Middle Click", .middleClick),
        ("Back", .back), ("Forward", .forward), ("Wheel Up", .wheelUp), ("Wheel Down", .wheelDown),
        ("DPI Cycle", .dpiCycle), ("DPI +", .dpiUp), ("DPI −", .dpiDown),
        ("Tilt Left", .tiltLeft), ("Tilt Right", .tiltRight), ("Show Desktop", .showDesktop),
        ("Mode Switch", .modeSwitch), ("Lighting Toggle", .lightingToggle), ("Disabled", .disabled),
        ("Play/Pause", .consumer(0xCD)), ("Next Track", .consumer(0xB5)), ("Previous Track", .consumer(0xB6)),
        ("Volume Up", .consumer(0xE9)), ("Volume Down", .consumer(0xEA)), ("Mute", .consumer(0xE2)),
        ("⌘C Copy", .key(modifiers: 0x08, usage: 0x06)), ("⌘V Paste", .key(modifiers: 0x08, usage: 0x19)),
        ("⌘X Cut", .key(modifiers: 0x08, usage: 0x1B)), ("⌘Z Undo", .key(modifiers: 0x08, usage: 0x1D)),
    ]

    public var displayName: String {
        Self.presets.first { $0.code == self }?.name ?? Packet.hex(bytes)
    }
}

/// The XS Flow Plus's onboard button slots, in the web app's order.
public enum OnboardButton: Int, CaseIterable, Sendable {
    case left = 1, right, middle, forward, back, modeSwitch, dpi, tiltLeft, tiltRight, showDesktop

    public var displayName: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .middle: "Middle (wheel click)"
        case .forward: "Forward"
        case .back: "Back"
        case .modeSwitch: "Mode switch"
        case .dpi: "DPI button"
        case .tiltLeft: "Wheel tilt left"
        case .tiltRight: "Wheel tilt right"
        case .showDesktop: "Show desktop"
        }
    }

    /// Factory defaults, from the web app's DEFAULT_CONFIG_TEMPLATE.
    public var factoryCode: ButtonCode {
        switch self {
        case .left: .leftClick
        case .right: .rightClick
        case .middle: .middleClick
        case .forward: .forward
        case .back: .back
        case .modeSwitch: .modeSwitch
        case .dpi: .dpiCycle
        case .tiltLeft: .tiltLeft
        case .tiltRight: .tiltRight
        case .showDesktop: .showDesktop
        }
    }
}

public enum PollingRate: UInt8, CaseIterable, Codable, Sendable {
    case hz125 = 8, hz250 = 4, hz500 = 2, hz1000 = 1, hz2000 = 17, hz4000 = 18, hz8000 = 20

    public var hertz: Int {
        switch self {
        case .hz125: 125
        case .hz250: 250
        case .hz500: 500
        case .hz1000: 1000
        case .hz2000: 2000
        case .hz4000: 4000
        case .hz8000: 8000
        }
    }

    public init?(hertz: Int) {
        guard let rate = Self.allCases.first(where: { $0.hertz == hertz }) else { return nil }
        self = rate
    }

    /// Rates the web app offers for a given `maxReportRate` from the status report.
    public static func supported(maxReportRate: UInt8) -> [PollingRate] {
        let base: [PollingRate] = [.hz125, .hz250, .hz500, .hz1000]
        switch maxReportRate {
        case 8: return base + [.hz2000, .hz4000, .hz8000]
        case 4: return base + [.hz2000, .hz4000]
        case 2: return base + [.hz2000]
        case 49: return [.hz125, .hz250]
        default: return base
        }
    }
}

public enum LightingMode: UInt8, CaseIterable, Codable, Sendable {
    case off = 0, rainbowFlow, breathe, steady, neon, marquee, rainbowSteady, wave

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .rainbowFlow: "Rainbow flow"
        case .breathe: "Breathe"
        case .steady: "Steady"
        case .neon: "Neon"
        case .marquee: "Marquee"
        case .rainbowSteady: "Rainbow steady"
        case .wave: "Wave"
        }
    }

    public var usesBrightness: Bool { self == .steady || self == .rainbowSteady }
    public var usesSpeed: Bool { [.rainbowFlow, .breathe, .neon, .marquee, .wave].contains(self) }
    public var usesDirection: Bool { self == .rainbowFlow }
}

public struct RGB: Codable, Hashable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }

    public init?(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF))
    }

    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
    public static let defaultLevelColor = RGB(0xEA, 0x5E, 0x56)
}

/// Encoders for every command the web app sends. Each returns full 31-byte
/// report bodies ready for `SetReport(Feature, 6, …)`.
public enum MouseProtocol {
    public enum Command: UInt8 {
        case buttons = 0x01, dpi = 0x02, dpiColors = 0x03, pollingRate = 0x04, liftOff = 0x05
        case lighting = 0x06, power = 0x07, sensor = 0x08, factoryReset = 0x0F
        case macroData = 0x10, macroErase = 0x11
    }

    /// Onboard button map. `codes` is indexed like `OnboardButton` (slot 1 first).
    /// The firmware stores back/forward (slots 4/5) swapped relative to the UI order.
    public static func buttons(_ codes: [ButtonCode], seq: inout CommandSequence) -> [[UInt8]] {
        func code(_ i: Int) -> [UInt8] { i < codes.count ? codes[i].bytes : ButtonCode.unset.bytes }
        func firstPacketIndex(_ q: Int) -> Int { q == 3 ? 4 : q == 4 ? 3 : q }

        if codes.count <= 9 {
            let payload = (0..<codes.count).flatMap { code(firstPacketIndex($0)) }
            return [Packet.build(cmd: Command.buttons.rawValue, seq: seq.next(), sub: 1, payload: payload, pad: 0xFF)]
        }
        let first = (0..<9).flatMap { code(firstPacketIndex($0)) }
        let second = (9..<min(codes.count, 18)).flatMap { code($0) }
        return [
            Packet.build(cmd: Command.buttons.rawValue, seq: seq.next(), sub: 2, payload: first, pad: 0xFF),
            Packet.build(cmd: Command.buttons.rawValue, seq: seq.next(), sub: 0x12, payload: second, pad: 0xFF),
        ]
    }

    /// Sensors 3395 (0x95) and 3950 (0x50) use 50-DPI steps; everything else 100.
    static func dpiStep(sensorType: UInt8) -> Int { sensorType == 0x95 || sensorType == 0x50 ? 50 : 100 }

    public enum Axis: UInt8 { case x = 2, y = 0x12 }

    /// DPI levels for one axis. The web app sends X, waits ~200 ms, then Y with the same values.
    public static func dpi(axis: Axis, levels: [Int], currentLevel: Int, sensorType: UInt8, seq: inout CommandSequence) -> [UInt8] {
        let count = min(levels.count, 8)
        var payload: [UInt8] = [UInt8(clamping: currentLevel), UInt8((1 << count) - 1)]
        let step = dpiStep(sensorType: sensorType)
        for i in 0..<8 {
            let dpi = i < count ? levels[i] : 0
            let raw = dpi / step - 1 // unused slots become -1 → FF FF, as in the web app
            payload += [UInt8(raw & 0xFF), UInt8((raw >> 8) & 0xFF)]
        }
        return Packet.build(cmd: Command.dpi.rawValue, seq: seq.next(), sub: axis.rawValue, payload: payload, pad: 0xFF)
    }

    /// Indicator colour per DPI level (8 slots).
    public static func dpiColors(_ colors: [RGB], seq: inout CommandSequence) -> [UInt8] {
        let padded = (0..<8).map { $0 < colors.count ? colors[$0] : .defaultLevelColor }
        let payload = padded.flatMap { [$0.r, $0.g, $0.b] }
        return Packet.build(cmd: Command.dpiColors.rawValue, seq: seq.next(), sub: 1, payload: payload, pad: 0xFF)
    }

    public static func pollingRate(_ rate: PollingRate, seq: inout CommandSequence) -> [UInt8] {
        Packet.build(cmd: Command.pollingRate.rawValue, seq: seq.next(), sub: 1, payload: [rate.rawValue], pad: 0x00)
    }

    /// Lift-off distance: 1 = 1 mm, 2 = 2 mm.
    public static func liftOff(millimetres: UInt8, seq: inout CommandSequence) -> [UInt8] {
        Packet.build(cmd: Command.liftOff.rawValue, seq: seq.next(), sub: 1, payload: [millimetres], pad: 0xFF)
    }

    /// brightness 1…4, speed 1…3; only the fields the mode uses are sent (others 0).
    public static func lighting(mode: LightingMode, brightness: Int, speed: Int, direction: UInt8, seq: inout CommandSequence) -> [UInt8] {
        let b = mode.usesBrightness ? UInt8(min(max(brightness, 1), 4)) << 4 : 0
        let s = mode.usesSpeed ? UInt8(min(max(speed, 1), 3)) : 0
        let payload: [UInt8] = [0xFF, mode.rawValue, b | s, direction]
        return Packet.build(cmd: Command.lighting.rawValue, seq: seq.next(), sub: 1, payload: payload, pad: 0xFF)
    }

    /// Sleep after 1…15 minutes idle.
    public static func power(sleepMinutes: Int, moveWakeup: Bool, moveLighting: Bool, seq: inout CommandSequence) -> [UInt8] {
        let payload: [UInt8] = [UInt8(min(max(sleepMinutes, 1), 15)), moveWakeup ? 1 : 0, moveLighting ? 1 : 0]
        return Packet.build(cmd: Command.power.rawValue, seq: seq.next(), sub: 1, payload: payload, pad: 0xFF)
    }

    public static func sensor(angleSnap: Bool, motionSync: Bool, ripple: Bool, seq: inout CommandSequence) -> [UInt8] {
        let payload: [UInt8] = [angleSnap ? 1 : 0, motionSync ? 1 : 0, ripple ? 1 : 0]
        return Packet.build(cmd: Command.sensor.rawValue, seq: seq.next(), sub: 1, payload: payload, pad: 0xFF)
    }

    public static func factoryReset(seq: inout CommandSequence) -> [UInt8] {
        Packet.build(cmd: Command.factoryReset.rawValue, seq: seq.next(), sub: 1, payload: [0xFF], pad: 0xFF)
    }
}

/// Parsed input report 4 (the dongle pushes it on connect and whenever something changes).
public struct DeviceStatus: Sendable, Equatable {
    public var linkStatus: UInt8
    public var dpiLevel: UInt8
    public var reportRate: UInt8
    public var batteryPercent: UInt8
    public var batteryStatus: UInt8
    public var lightingMode: UInt8
    public var maxReportRate: UInt8
    public var sensorType: UInt8

    /// `bytes` excludes the report ID, like WebHID's `event.data`.
    public init?(report bytes: [UInt8]) {
        guard bytes.count >= 9 else { return nil }
        linkStatus = bytes[0]
        dpiLevel = bytes[1]
        reportRate = bytes[2]
        batteryPercent = bytes[3]
        batteryStatus = bytes[4]
        lightingMode = bytes[5]
        maxReportRate = bytes[7]
        sensorType = bytes[8]
    }

    public var pollingRate: PollingRate? { PollingRate(rawValue: reportRate) }
    public var isCharging: Bool { batteryStatus != 0 }

    public var sensorName: String {
        [0x11: "PAW3311", 0x95: "PAW3395", 0x50: "PAW3950", 0x20: "PAW3220", 0x12: "PAW3212",
         0x09: "PAW3809", 0x03: "S203", 0x06: "S205", 0x70: "OM70"][Int(sensorType)] ?? String(format: "0x%02X", sensorType)
    }

    /// Default DPI table per sensor (web app SENSOR_CONFIGS); XS Flow Plus reports S203 by default.
    public var defaultDPILevels: [Int] {
        switch sensorType {
        case 0x11: [400, 800, 1600, 2400, 3200, 6400, 12000]
        case 0x95: [400, 800, 1600, 3200, 6400, 26000]
        case 0x50, 0x70: [400, 800, 1600, 3200, 6400, 30000]
        case 0x20: [400, 800, 1600, 2400, 3200, 6400, 8000]
        case 0x12: [400, 800, 1200, 1600, 2400, 3200, 4800]
        case 0x09: [400, 800, 1600, 2400, 3200, 4800, 6000]
        case 0x06: [400, 800, 1600, 2400, 3200, 6400, 12800]
        default: [400, 800, 1200, 1600, 2400, 3200, 6400]
        }
    }
}
