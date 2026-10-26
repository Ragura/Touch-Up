import SwiftUI

struct PermissionStatusView: View {
    @ObservedObject var permissions: PermissionController
    var quit: () -> Void = { NSApp.terminate(nil) }

    private var controlTitle: String {
        if #available(macOS 27.0, *) { return "Device Control & Data Access" }
        return "Accessibility"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            permissionRow(controlTitle, granted: permissions.snapshot.accessibility, permission: .accessibility)
            permissionRow("Input Monitoring", granted: permissions.snapshot.inputMonitoring, permission: .inputMonitoring)
            if permissions.inputMonitoringNeedsRestart {
                HStack(alignment: .top) {
                    Text("Input access changed. Quit and reopen Touch Up.")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer(minLength: 4)
                    Button("Quit", action: quit).controlSize(.small)
                }
            } else if !permissions.snapshot.inputMonitoring {
                Text("After allowing input, quit and reopen Touch Up.")
                    .font(.caption).foregroundColor(.secondary)
            }
            if permissions.settingsOpenFailed {
                Text("Open System Settings → Privacy & Security.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func permissionRow(_ title: String, granted: Bool, permission: TouchPermission) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(granted ? .green : .orange)
                .accessibilityHidden(true)
            Text(title).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if granted {
                Text("Allowed").font(.caption).foregroundColor(.secondary)
            } else {
                Button("Allow…") { permissions.request(permission) }
                    .controlSize(.small)
                    .accessibilityLabel("Allow \(title)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title): \(granted ? "Allowed" : "Not granted")")
    }
}
