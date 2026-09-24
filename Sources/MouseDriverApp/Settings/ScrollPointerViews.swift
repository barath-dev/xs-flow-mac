import FlowCore
import SwiftUI

struct ScrollSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                ScrollFields(settings: $model.config.scroll)
            } footer: {
                Text("Applies to the XS Flow only. Your trackpad keeps the system scroll direction. Apps can override this in the Apps tab.")
            }
        }
        .formStyle(.grouped)
    }
}

struct ScrollFields: View {
    @Binding var settings: ScrollSettings

    var body: some View {
        Toggle("Reverse vertical scrolling", isOn: $settings.reverseVertical)
        Toggle("Reverse horizontal scrolling (wheel tilt)", isOn: $settings.reverseHorizontal)
        LabeledContent("Scroll speed") {
            HStack {
                Slider(value: $settings.speed, in: 0.25...5, step: 0.25)
                Text(String(format: "%.2g×", settings.speed)).monospacedDigit().frame(width: 40, alignment: .trailing)
            }
        }
    }
}

struct PointerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Custom tracking speed for this mouse", isOn: Binding(
                    get: { model.config.pointer.trackingSpeed != nil },
                    set: { model.config.pointer.trackingSpeed = $0 ? (PointerApplier().currentTrackingSpeed ?? 1) : nil }
                ))
                if let speed = model.config.pointer.trackingSpeed {
                    LabeledContent("Tracking speed") {
                        HStack {
                            Text("Slow").font(.caption)
                            Slider(value: Binding(get: { speed }, set: { model.config.pointer.trackingSpeed = $0 }), in: 0...3)
                            Text("Fast").font(.caption)
                        }
                    }
                }
            } footer: {
                Text("Overrides System Settings → Mouse → Tracking speed for the XS Flow only. Turn it off to restore the system value.")
            }

            Section {
                Toggle("Custom scroll acceleration", isOn: Binding(
                    get: { model.config.pointer.scrollAcceleration != nil },
                    set: { model.config.pointer.scrollAcceleration = $0 ? 0.3125 : nil }
                ))
                if let accel = model.config.pointer.scrollAcceleration {
                    Slider(value: Binding(get: { accel }, set: { model.config.pointer.scrollAcceleration = $0 }), in: 0...3) {
                        Text("Scroll acceleration")
                    }
                }
            } footer: {
                Text("0 gives constant, notch-by-notch scrolling. Higher values scroll further when you spin the wheel fast.")
            }

            if model.transports.contains(where: { $0 != .bluetooth }) {
                Section {
                    Text("The sensor's own DPI is set in the Hardware tab.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AppsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading) {
            HStack {
                Text("Per-app profiles override the Default profile's buttons and scrolling while that app is in front.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add App…", action: addApp)
            }
            if model.config.profiles.count <= 1 {
                ContentUnavailableView("No app profiles", systemImage: "app.dashed",
                                       description: Text("Add an app, then pick it from the profile menu in the Buttons tab."))
            } else {
                Form {
                    ForEach(Array(model.config.profiles.indices.dropFirst()), id: \.self) { i in
                        Section {
                            TextField("Name", text: $model.config.profiles[i].name)
                            LabeledContent("Apps", value: model.config.profiles[i].bundleIDs.joined(separator: ", "))
                            LabeledContent("Button overrides", value: "\(model.config.profiles[i].bindings.count)")
                            Toggle("Override scrolling", isOn: Binding(
                                get: { model.config.profiles[i].scroll != nil },
                                set: { model.config.profiles[i].scroll = $0 ? model.config.scroll : nil }
                            ))
                            if model.config.profiles[i].scroll != nil {
                                ScrollFields(settings: Binding(
                                    get: { model.config.profiles[i].scroll ?? ScrollSettings() },
                                    set: { model.config.profiles[i].scroll = $0 }
                                ))
                            }
                            Button("Remove Profile", role: .destructive) {
                                model.config.profiles.remove(at: i)
                            }
                        } header: {
                            Text(model.config.profiles[i].name)
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
    }

    private func addApp() {
        guard let url = ActionEditor.chooseApp(),
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        if model.config.profiles.contains(where: { $0.bundleIDs.contains(id) }) { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        model.config.profiles.append(Profile(name: name, bundleIDs: [id]))
    }
}
