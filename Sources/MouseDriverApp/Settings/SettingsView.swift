import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if !model.permissionsGranted {
                PermissionsView()
                    .padding()
                Divider()
            }
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
            TabView {
                MiceView()
                    .tabItem { Label("Mice", systemImage: "computermouse.fill") }
                ButtonsView()
                    .tabItem { Label("Buttons", systemImage: "computermouse") }
                ScrollSettingsView()
                    .tabItem { Label("Scrolling", systemImage: "arrow.up.and.down") }
                PointerView()
                    .tabItem { Label("Pointer", systemImage: "cursorarrow.motionlines") }
                AppsView()
                    .tabItem { Label("Apps", systemImage: "app.badge") }
                if model.hardwareEnabled {
                    HardwareView()
                        .tabItem { Label("Hardware", systemImage: "cpu") }
                }
                GeneralView()
                    .tabItem { Label("General", systemImage: "gearshape") }
            }
            .padding()
        }
    }
}

struct GeneralView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Toggle("Enable remapping", isOn: $model.config.enabled)
            Toggle("Launch at login", isOn: $model.launchAtLogin)
            LabeledContent("Mice", value: model.connectionSummary)
            LabeledContent("Engine", value: model.engineRunning ? "Running" : "Stopped")
            LabeledContent("Config file") {
                Button(model.store.url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([model.store.url])
                }
                .buttonStyle(.link)
            }
        }
        .formStyle(.grouped)
    }
}
