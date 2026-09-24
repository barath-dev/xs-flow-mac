import Foundation
import Testing
@testable import FlowCore

@Suite struct ConfigTests {
    let config = Config(profiles: [
        Profile(name: "Default", bindings: [
            ButtonBinding(button: 4, action: .shortcut(combo: KeyCombo(keyCode: 33, command: true))),
            ButtonBinding(button: 5, action: .system(action: .missionControl)),
        ]),
        Profile(name: "Music", bundleIDs: ["com.apple.Music"], bindings: [
            ButtonBinding(button: 4, action: .media(key: .previous)),
        ], scroll: ScrollSettings(speed: 3)),
    ])

    @Test func roundTrips() throws {
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data) == config)
    }

    @Test func appProfileOverridesPerButton() {
        #expect(config.action(forButton: 4, bundleID: "com.apple.Music") == .media(key: .previous))
        // Not overridden in the app profile → falls back to default.
        #expect(config.action(forButton: 5, bundleID: "com.apple.Music") == .system(action: .missionControl))
        #expect(config.action(forButton: 4, bundleID: "com.apple.Safari") == .shortcut(combo: KeyCombo(keyCode: 33, command: true)))
        #expect(config.action(forButton: 3, bundleID: nil) == nil)
    }

    @Test func scrollOverride() {
        #expect(config.scrollSettings(bundleID: "com.apple.Music").speed == 3)
        #expect(config.scrollSettings(bundleID: "com.apple.Safari").speed == 1)
    }

    @Test func decodesMinimalHandWrittenConfig() throws {
        let json = """
        {"profiles":[{"name":"Default","bindings":[
          {"button":4,"action":{"shortcut":{"combo":{"keyCode":33,"command":true}}}}
        ]}]}
        """
        let decoded = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(decoded.enabled)
        #expect(decoded.action(forButton: 4, bundleID: nil) == .shortcut(combo: KeyCombo(keyCode: 33, command: true)))
    }

    @Test func emptyProfilesGetADefault() throws {
        let decoded = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(decoded.profiles.count == 1)
    }

    @Test func parsesCombos() {
        #expect(KeyCodes.parseCombo("cmd+shift+[") == KeyCombo(keyCode: 33, command: true, shift: true))
        #expect(KeyCodes.parseCombo("ctrl+Left")?.control == true)
        #expect(KeyCodes.parseCombo("hyper+x") == nil)
        #expect(KeyCombo(keyCode: 33, command: true, shift: true).displayName == "⇧⌘[")
    }
}
