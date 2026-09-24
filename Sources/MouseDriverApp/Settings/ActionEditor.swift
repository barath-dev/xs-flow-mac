import AppKit
import FlowCore
import SwiftUI

/// Edits one `Action`: a kind picker plus the fields that kind needs.
struct ActionEditor: View {
    @Binding var action: Action

    enum Kind: String, CaseIterable, Identifiable {
        case shortcut = "Keyboard shortcut"
        case system = "System action"
        case media = "Media key"
        case mouseButton = "Mouse button"
        case scrollModifier = "Wheel modifier (hold)"
        case openApp = "Open app"
        case openURL = "Open URL"
        case shell = "Run shell command"
        case disabled = "Do nothing"
        var id: String { rawValue }
    }

    private var kind: Kind {
        switch action {
        case .disabled: .disabled
        case .mouseButton: .mouseButton
        case .shortcut: .shortcut
        case .system: .system
        case .media: .media
        case .openApp: .openApp
        case .openURL: .openURL
        case .shell: .shell
        case .scrollModifier: .scrollModifier
        }
    }

    var body: some View {
        Picker("Action", selection: Binding(get: { kind }, set: { action = Self.defaultAction(for: $0) })) {
            ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
        }
        detail
    }

    @ViewBuilder private var detail: some View {
        switch action {
        case .shortcut(let combo):
            LabeledContent("Shortcut") {
                ShortcutRecorder(combo: Binding(get: { combo }, set: { action = .shortcut(combo: $0) }))
            }
        case .system(let a):
            Picker("System action", selection: Binding(get: { a }, set: { action = .system(action: $0) })) {
                ForEach(SystemAction.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        case .media(let key):
            Picker("Key", selection: Binding(get: { key }, set: { action = .media(key: $0) })) {
                ForEach(MediaKey.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        case .mouseButton(let n):
            Picker("Acts as", selection: Binding(get: { n }, set: { action = .mouseButton(number: $0) })) {
                ForEach(1...8, id: \.self) { Text(MouseButtons.name($0)).tag($0) }
            }
        case .scrollModifier(let mode):
            Picker("While held", selection: Binding(get: { mode }, set: { action = .scrollModifier(mode: $0) })) {
                ForEach(ScrollModifier.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        case .openApp(let path):
            LabeledContent("App") {
                HStack {
                    Text(path.isEmpty ? "None" : URL(fileURLWithPath: path).lastPathComponent)
                        .foregroundStyle(path.isEmpty ? .secondary : .primary)
                    Button("Choose…") {
                        if let url = Self.chooseApp() { action = .openApp(path: url.path) }
                    }
                }
            }
        case .openURL(let url):
            TextField("URL", text: Binding(get: { url }, set: { action = .openURL(url: $0) }), prompt: Text("https://…"))
        case .shell(let command):
            TextField("Command", text: Binding(get: { command }, set: { action = .shell(command: $0) }), prompt: Text("open ~/Downloads"))
                .font(.system(.body, design: .monospaced))
        case .disabled:
            Text("The button is swallowed.").foregroundStyle(.secondary)
        }
    }

    static func defaultAction(for kind: Kind) -> Action {
        switch kind {
        case .shortcut: .shortcut(combo: KeyCombo(keyCode: 33, command: true))
        case .system: .system(action: .missionControl)
        case .media: .media(key: .playPause)
        case .mouseButton: .mouseButton(number: 3)
        case .scrollModifier: .scrollModifier(mode: .horizontal)
        case .openApp: .openApp(path: "")
        case .openURL: .openURL(url: "")
        case .shell: .shell(command: "")
        case .disabled: .disabled
        }
    }

    static func chooseApp() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Click, then press a key combination.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Type shortcut…" : combo.displayName) {
            recording ? stop() : start()
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                stop() // plain Escape cancels
                return nil
            }
            let flags = event.modifierFlags
            combo = KeyCombo(
                keyCode: event.keyCode,
                command: flags.contains(.command),
                option: flags.contains(.option),
                control: flags.contains(.control),
                shift: flags.contains(.shift)
            )
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}
