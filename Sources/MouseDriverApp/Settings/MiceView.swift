import FlowCore
import SwiftUI

/// Connected mice, and which of them MouseDriver customises.
struct MiceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                if model.mice.isEmpty {
                    Text("No mouse connected. Trackpads aren't listed; they always keep their system settings.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.mice) { mouse in
                    Toggle(isOn: Binding(
                        get: { model.isCustomized(mouse) },
                        set: { model.setCustomized(mouse.model, $0) }
                    )) {
                        Text(mouse.name)
                        Text(details(mouse))
                    }
                }
            } header: {
                Text("Connected")
            } footer: {
                Text("Your buttons, scrolling and pointer settings apply to every mouse switched on here. Switch a mouse off to leave it exactly as macOS has it.")
            }

            let offline = model.config.excludedDevices.filter { id in !model.mice.contains { $0.model == id } }
            if !offline.isEmpty {
                Section("Switched off, not connected") {
                    ForEach(offline, id: \.self) { id in
                        LabeledContent(id.name) {
                            Button("Switch On") { model.setCustomized(id, true) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func details(_ mouse: PointingDevice) -> String {
        var parts = [mouse.transportLabel]
        if let battery = model.battery(for: mouse) { parts.append("\(battery)% battery") }
        if mouse.isXSFlow { parts.append("Amkette XS Flow") }
        return parts.joined(separator: " · ")
    }
}
