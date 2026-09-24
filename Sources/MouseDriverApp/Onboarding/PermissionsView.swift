import SwiftUI

struct PermissionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MouseDriver needs one permission to customise your mouse")
                .font(.headline)
            row(
                granted: model.accessibilityGranted,
                title: "Accessibility",
                detail: "To change what your mouse's buttons and wheel do. MouseDriver only watches mouse events and never reads your keyboard.",
                service: "Accessibility",
                action: model.requestAccessibility
            )
            Text("""
            Already switched on in System Settings but still shown here? That entry belongs to an older build \
            of MouseDriver, because each rebuild counts as a new app to macOS. Click “Reset”, then “Grant…” and switch it on again.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Button("Re-check") { model.startEngineWhenPermitted() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(granted: Bool, title: String, detail: String, service: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
            VStack(alignment: .leading) {
                Text(title).bold()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Reset") { model.resetPermission(service) }
                    .help("Remove MouseDriver's stale entry from this list")
                Button("Grant…", action: action)
            }
        }
    }
}
