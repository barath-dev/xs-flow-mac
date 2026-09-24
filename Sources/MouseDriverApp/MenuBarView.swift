import FlowCore
import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model

        Text("XS Flow · \(model.connectionSummary)\(batteryText)")
        if !model.permissionsGranted {
            Text("⚠︎ Permissions needed. Open Settings")
        } else if !model.engineRunning {
            Text("⚠︎ Engine not running")
        }
        if let action = model.lastAction {
            Text("Last: \(action)")
        }

        Divider()

        Toggle("Enable remapping", isOn: $model.config.enabled)

        if model.config.profiles.count > 1 {
            Text("\(model.config.profiles.count - 1) app profile(s)")
        }

        Divider()

        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")

        Button("Quit MouseDriver") {
            model.engine.stop()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var batteryText: String {
        guard let percent = model.batteryPercent else { return "" }
        return " · \(percent)%\(model.hardwareStatus?.isCharging == true ? " ⚡︎" : "")"
    }
}
