import ApplicationServices
import IOKit.hid
import SwiftUI

@main
struct MouseDriverApp: App {
    @State private var model: AppModel

    init() {
        // `open -n build/MouseDriver.app --args --check-permissions --stdout …` prints what
        // macOS reports for *this* build. Launch via `open`: when the binary is run
        // directly, TCC checks the terminal instead.
        if CommandLine.arguments.contains("--check-permissions") {
            let listen = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            print("""
            bundle            \(Bundle.main.bundlePath)
            accessibility     \(AXIsProcessTrusted() ? "granted" : "NOT granted")
            input monitoring  \(listen == kIOHIDAccessTypeGranted ? "granted" : listen == kIOHIDAccessTypeDenied ? "denied" : "not decided")
            """)
            exit(0)
        }
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            Image(systemName: model.mice.isEmpty ? "computermouse" : "computermouse.fill")
        }

        Window("MouseDriver", id: "settings") {
            SettingsView()
                .environment(model)
                .frame(minWidth: 640, minHeight: 480)
        }
        .windowResizability(.contentMinSize)
    }
}
