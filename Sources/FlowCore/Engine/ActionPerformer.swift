import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Marks events we synthesise so our own tap lets them through untouched.
let syntheticEventMarker: Int64 = 0x464C_4F57 // "FLOW"

/// Carries out bound actions. Actions with a meaningful "hold" (shortcuts) get
/// separate press/release; everything else fires once on press.
public final class ActionPerformer {
    private let source = CGEventSource(stateID: .hidSystemState)

    public init() {}

    public func press(_ action: Action) {
        switch action {
        case .shortcut(let combo): postKey(combo, down: true)
        case .system(let a): perform(a)
        case .media(let key): postMedia(key)
        case .openApp(let path):
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
        case .openURL(let string):
            if let url = URL(string: string) { NSWorkspace.shared.open(url) }
        case .shell(let command): runShell(command)
        case .disabled, .mouseButton, .scrollModifier: break // handled by the engine
        }
    }

    public func release(_ action: Action) {
        if case .shortcut(let combo) = action { postKey(combo, down: false) }
    }

    // MARK: Keyboard

    public func postKey(_ combo: KeyCombo, down: Bool) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: down) else { return }
        var flags: CGEventFlags = []
        if combo.command { flags.insert(.maskCommand) }
        if combo.option { flags.insert(.maskAlternate) }
        if combo.control { flags.insert(.maskControl) }
        if combo.shift { flags.insert(.maskShift) }
        if [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow].contains(Int(combo.keyCode)) {
            flags.insert([.maskNumericPad, .maskSecondaryFn]) // how the real arrow keys arrive
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        event.post(tap: .cghidEventTap)
    }

    private func tap(_ combo: KeyCombo) {
        postKey(combo, down: true)
        postKey(combo, down: false)
    }

    // MARK: System actions

    private typealias CoreDockSendNotification = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void
    private lazy var coreDockSend: CoreDockSendNotification? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(sym, to: CoreDockSendNotification.self)
    }()

    private func dock(_ notification: String, fallbackApp: String?) {
        if let send = coreDockSend {
            send(notification as CFString, nil)
        } else if let app = fallbackApp {
            NSWorkspace.shared.open(URL(fileURLWithPath: app))
        }
    }

    private func perform(_ action: SystemAction) {
        switch action {
        case .missionControl:
            dock("com.apple.expose.awake", fallbackApp: "/System/Applications/Mission Control.app")
        case .appExpose:
            dock("com.apple.expose.front.awake", fallbackApp: nil)
        case .showDesktop:
            dock("com.apple.showdesktop.awake", fallbackApp: nil)
        case .launchpad:
            dock("com.apple.launchpad.toggle", fallbackApp: "/System/Applications/Apps.app")
        case .spaceLeft:
            tap(KeyCombo(keyCode: UInt16(kVK_LeftArrow), control: true))
        case .spaceRight:
            tap(KeyCombo(keyCode: UInt16(kVK_RightArrow), control: true))
        case .screenshot:
            tap(KeyCombo(keyCode: UInt16(kVK_ANSI_5), command: true, shift: true))
        case .lockScreen:
            tap(KeyCombo(keyCode: UInt16(kVK_ANSI_Q), command: true, control: true))
        }
    }

    // MARK: Media keys

    private func postMedia(_ key: MediaKey) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key.nxKeyType << 16) | ((down ? 0xA : 0xB) << 8))
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Shell

    private func runShell(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
