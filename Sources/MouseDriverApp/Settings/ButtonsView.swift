import FlowCore
import SwiftUI

struct ButtonsView: View {
    @Environment(AppModel.self) private var model
    @State private var profileIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Profile", selection: $profileIndex) {
                    ForEach(model.config.profiles.indices, id: \.self) { i in
                        Text(i == 0 ? "Default (all apps)" : model.config.profiles[i].name).tag(i)
                    }
                }
                .frame(maxWidth: 320)
                Spacer()
                if model.isCapturing {
                    Text("Press a button on your mouse…").foregroundStyle(.secondary)
                    Button("Cancel") { model.cancelCapture() }
                } else {
                    Button("Add Button…") {
                        model.captureButton { button in
                            if model.binding(profile: profileIndex, button: button) == nil {
                                model.setBinding(profile: profileIndex, button: button, action: defaultAction(for: button))
                            }
                        }
                    }
                    .disabled(!model.engineRunning)
                }
            }

            if profileIndex > 0 {
                Text("Buttons listed here override the Default profile while \(model.config.profiles[profileIndex].name) is in front.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let bindings = profileIndex < model.config.profiles.count ? model.config.profiles[profileIndex].bindings : []
            if bindings.isEmpty {
                ContentUnavailableView(
                    "No custom buttons",
                    systemImage: "computermouse",
                    description: Text("Click “Add Button…”, then press the mouse button you want to customise. Unlisted buttons keep their normal behaviour.")
                )
            } else {
                Form {
                    ForEach(bindings) { binding in
                        Section {
                            ActionEditor(action: Binding(
                                get: { model.binding(profile: profileIndex, button: binding.button) ?? .disabled },
                                set: { model.setBinding(profile: profileIndex, button: binding.button, action: $0) }
                            ))
                        } header: {
                            HStack {
                                Text(MouseButtons.name(binding.button))
                                Spacer()
                                Button(role: .destructive) {
                                    model.setBinding(profile: profileIndex, button: binding.button, action: nil)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Restore this button's normal behaviour")
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }

            if binding(forLeftClickWarning: bindings) {
                Label("Remapping Left Click can make the mouse hard to use; the trackpad keeps working.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onChange(of: model.config.profiles.count) { _, count in
            if profileIndex >= count { profileIndex = 0 }
        }
    }

    private func binding(forLeftClickWarning bindings: [ButtonBinding]) -> Bool {
        bindings.contains { $0.button == 1 }
    }

    private func defaultAction(for button: Int) -> Action {
        switch button {
        case 4: .shortcut(combo: KeyCombo(keyCode: 33, command: true)) // ⌘[
        case 5: .shortcut(combo: KeyCombo(keyCode: 30, command: true)) // ⌘]
        case 3: .system(action: .missionControl)
        default: .mouseButton(number: button)
        }
    }
}
