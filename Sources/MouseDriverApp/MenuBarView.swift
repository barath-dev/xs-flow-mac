import FlowCore
import SwiftUI

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model

        if model.mice.isEmpty {
            Text("No mouse connected")
        }
        ForEach(model.mice) { mouse in
            Text("\(mouse.name) · \(mouse.transportLabel)\(batteryText(mouse))\(model.isCustomized(mouse) ? "" : " · off")")
        }
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

    private func batteryText(_ mouse: PointingDevice) -> String {
        guard let percent = model.battery(for: mouse) else { return "" }
        let charging = mouse.isXSFlow && !mouse.isBluetooth && model.hardwareStatus?.isCharging == true
        return " · \(percent)%\(charging ? " ⚡︎" : "")"
    }
}
