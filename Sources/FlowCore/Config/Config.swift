import Foundation

/// A keyboard shortcut: a macOS virtual key code plus modifiers.
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var command = false
    public var option = false
    public var control = false
    public var shift = false

    public init(keyCode: UInt16, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false) {
        self.keyCode = keyCode
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    public var displayName: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        return s + KeyCodes.name(for: keyCode)
    }
}

public enum SystemAction: String, Codable, CaseIterable, Sendable {
    case missionControl, appExpose, showDesktop, launchpad
    case spaceLeft, spaceRight
    case screenshot, lockScreen

    public var displayName: String {
        switch self {
        case .missionControl: "Mission Control"
        case .appExpose: "App Exposé"
        case .showDesktop: "Show Desktop"
        case .launchpad: "Launchpad / Apps"
        case .spaceLeft: "Move Space Left"
        case .spaceRight: "Move Space Right"
        case .screenshot: "Screenshot (⇧⌘5)"
        case .lockScreen: "Lock Screen"
        }
    }
}

public enum MediaKey: String, Codable, CaseIterable, Sendable {
    case playPause, next, previous, volumeUp, volumeDown, mute, brightnessUp, brightnessDown

    /// NX_KEYTYPE_* values from IOKit/hidsystem/ev_keymap.h.
    var nxKeyType: Int32 {
        switch self {
        case .volumeUp: 0
        case .volumeDown: 1
        case .brightnessUp: 2
        case .brightnessDown: 3
        case .mute: 7
        case .playPause: 16
        case .next: 17
        case .previous: 18
        }
    }

    public var displayName: String {
        switch self {
        case .playPause: "Play / Pause"
        case .next: "Next Track"
        case .previous: "Previous Track"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        case .brightnessUp: "Brightness Up"
        case .brightnessDown: "Brightness Down"
        }
    }
}

/// While the button is held, the wheel behaves differently.
public enum ScrollModifier: String, Codable, CaseIterable, Sendable {
    case horizontal, zoom

    public var displayName: String {
        switch self {
        case .horizontal: "Hold: wheel scrolls horizontally"
        case .zoom: "Hold: wheel zooms (⌘ + scroll)"
        }
    }
}

public enum Action: Codable, Hashable, Sendable {
    case disabled
    /// Emit another mouse button instead (HID numbering: 1 left, 2 right, 3 middle, 4 back, 5 forward…).
    case mouseButton(number: Int)
    case shortcut(combo: KeyCombo)
    case system(action: SystemAction)
    case media(key: MediaKey)
    case openApp(path: String)
    case openURL(url: String)
    case shell(command: String)
    case scrollModifier(mode: ScrollModifier)

    public var displayName: String {
        switch self {
        case .disabled: "Disabled"
        case .mouseButton(let n): MouseButtons.name(n)
        case .shortcut(let combo): combo.displayName
        case .system(let a): a.displayName
        case .media(let k): k.displayName
        case .openApp(let path): "Open \(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)"
        case .openURL(let url): "Open \(url)"
        case .shell(let cmd): "Run: \(cmd)"
        case .scrollModifier(let m): m.displayName
        }
    }
}

public enum MouseButtons {
    public static func name(_ n: Int) -> String {
        switch n {
        case 1: "Left Click"
        case 2: "Right Click"
        case 3: "Middle Click"
        case 4: "Back (Button 4)"
        case 5: "Forward (Button 5)"
        default: "Button \(n)"
        }
    }
}

public struct ButtonBinding: Codable, Hashable, Sendable, Identifiable {
    /// HID button number as reported by the mouse (1-based).
    public var button: Int
    public var action: Action
    public var id: Int { button }

    public init(button: Int, action: Action) {
        self.button = button
        self.action = action
    }
}

public struct ScrollSettings: Codable, Hashable, Sendable {
    /// Flip the wheel for this mouse only (the trackpad keeps the system setting).
    public var reverseVertical = false
    public var reverseHorizontal = false
    /// Multiplier on wheel deltas. 1 = system behaviour.
    public var speed: Double = 1

    public init(reverseVertical: Bool = false, reverseHorizontal: Bool = false, speed: Double = 1) {
        self.reverseVertical = reverseVertical
        self.reverseHorizontal = reverseHorizontal
        self.speed = speed
    }
}

public struct Profile: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var name: String
    /// Apps this profile applies to. Empty for the default profile.
    public var bundleIDs: [String] = []
    /// Bindings. In an app profile these override the default profile's per button.
    public var bindings: [ButtonBinding] = []
    /// Overrides the default scroll settings when set.
    public var scroll: ScrollSettings?

    public init(name: String, bundleIDs: [String] = [], bindings: [ButtonBinding] = [], scroll: ScrollSettings? = nil) {
        self.name = name
        self.bundleIDs = bundleIDs
        self.bindings = bindings
        self.scroll = scroll
    }
}

public struct PointerSettings: Codable, Hashable, Sendable {
    /// Tracking speed for this mouse only, 0…3 like the System Settings slider. nil = leave untouched.
    public var trackingSpeed: Double?
    /// Scroll acceleration for this mouse only. nil = leave untouched.
    public var scrollAcceleration: Double?

    public init(trackingSpeed: Double? = nil, scrollAcceleration: Double? = nil) {
        self.trackingSpeed = trackingSpeed
        self.scrollAcceleration = scrollAcceleration
    }
}

public struct Config: Codable, Hashable, Sendable {
    public var enabled = true
    public var scroll = ScrollSettings()
    public var pointer = PointerSettings()
    /// profiles[0] is the default profile; the rest are per-app overrides.
    public var profiles: [Profile]

    public init(enabled: Bool = true, scroll: ScrollSettings = ScrollSettings(), pointer: PointerSettings = PointerSettings(), profiles: [Profile]) {
        self.enabled = enabled
        self.scroll = scroll
        self.pointer = pointer
        self.profiles = profiles.isEmpty ? [Profile(name: "Default")] : profiles
    }

    public static let `default` = Config(profiles: [
        Profile(name: "Default", bindings: [
            // Out of the box, keep the mouse's behaviour. Users add bindings in Settings.
        ]),
    ])

    public var defaultProfile: Profile { profiles[0] }

    /// The profile override for an app, if one exists.
    public func appProfile(for bundleID: String?) -> Profile? {
        guard let bundleID else { return nil }
        return profiles.dropFirst().first { $0.bundleIDs.contains(bundleID) }
    }

    /// The effective action for a button in the given app, or nil to pass the click through.
    public func action(forButton button: Int, bundleID: String?) -> Action? {
        if let app = appProfile(for: bundleID), let binding = app.bindings.first(where: { $0.button == button }) {
            return binding.action
        }
        return defaultProfile.bindings.first { $0.button == button }?.action
    }

    public func scrollSettings(bundleID: String?) -> ScrollSettings {
        appProfile(for: bundleID)?.scroll ?? scroll
    }
}

// MARK: Lenient decoding — hand-written config files may omit anything that has a default.

extension KeyCombo {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try c.decode(UInt16.self, forKey: .keyCode)
        command = try c.decodeIfPresent(Bool.self, forKey: .command) ?? false
        option = try c.decodeIfPresent(Bool.self, forKey: .option) ?? false
        control = try c.decodeIfPresent(Bool.self, forKey: .control) ?? false
        shift = try c.decodeIfPresent(Bool.self, forKey: .shift) ?? false
    }
}

extension ScrollSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reverseVertical = try c.decodeIfPresent(Bool.self, forKey: .reverseVertical) ?? false
        reverseHorizontal = try c.decodeIfPresent(Bool.self, forKey: .reverseHorizontal) ?? false
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
    }
}

extension Profile {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Profile"
        bundleIDs = try c.decodeIfPresent([String].self, forKey: .bundleIDs) ?? []
        bindings = try c.decodeIfPresent([ButtonBinding].self, forKey: .bindings) ?? []
        scroll = try c.decodeIfPresent(ScrollSettings.self, forKey: .scroll)
    }
}

extension Config {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            scroll: try c.decodeIfPresent(ScrollSettings.self, forKey: .scroll) ?? ScrollSettings(),
            pointer: try c.decodeIfPresent(PointerSettings.self, forKey: .pointer) ?? PointerSettings(),
            profiles: try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        )
    }
}
