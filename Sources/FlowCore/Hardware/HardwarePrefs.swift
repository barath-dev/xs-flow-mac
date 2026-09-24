import Foundation

/// The mouse can't report most of its onboard settings back, so we remember the
/// last values we wrote (factory defaults until then).
public struct HardwarePrefs: Codable, Equatable, Sendable {
    public var buttons: [ButtonCode] = OnboardButton.allCases.map(\.factoryCode)
    public var dpiLevels: [Int]?
    public var lightingMode: LightingMode = .off
    public var lightingSpeed = 3
    public var lightingBrightness = 4
    public var sleepMinutes = 1
    public var moveWakeup = true

    public init() {}

    static var url: URL {
        ConfigStore.defaultURL.deletingLastPathComponent().appendingPathComponent("hardware.json")
    }

    public static func load() -> HardwarePrefs {
        guard let data = try? Data(contentsOf: url),
              var prefs = try? JSONDecoder().decode(HardwarePrefs.self, from: data) else { return HardwarePrefs() }
        if prefs.buttons.count != OnboardButton.allCases.count { prefs.buttons = HardwarePrefs().buttons }
        return prefs
    }

    public func save() {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: Self.url, options: .atomic)
    }
}
