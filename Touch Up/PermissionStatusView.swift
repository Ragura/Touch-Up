import SwiftUI

struct PermissionStatusView: View {
    @ObservedObject var permissions: PermissionController
    @ObservedObject var restarter: RestartController

    private var controlTitle: String {
        if #available(macOS 27.0, *) { return "Device Control & Data Access" }
        return "Accessibility"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            permissionRow(controlTitle, granted: permissions.snapshot.accessibility, permission: .accessibility)
            permissionRow("Input Monitoring", granted: permissions.snapshot.inputMonitoring, permission: .inputMonitoring)
            if permissions.inputMonitoringNeedsRestart || !permissions.snapshot.accessibility || !permissions.snapshot.inputMonitoring {
                HStack(alignment: .top) {
                    Text(permissions.inputMonitoringNeedsRestart
                         ? "Permissions changed. Quit and reopen Touch Up."
                         : "After enabling permissions in Settings, quit and reopen Touch Up.")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer(minLength: 4)
                    Button("Quit and Reopen", action: restarter.restart)
                        .controlSize(.small)
                        .disabled(restarter.isRestarting)
                }

            }
            if restarter.failed {
                Text("Could not reopen Touch Up. Quit and open it from Applications.")
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
                let requested = permissions.requestedPermissions.contains(permission)
                Button(requested ? "Open Settings" : "Allow…") {
                    if requested { permissions.openSettings(permission) }
                    else { permissions.request(permission) }
                }
                .controlSize(.small)
                .accessibilityLabel(requested ? "Open Settings for \(title)" : "Allow \(title)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title): \(granted ? "Allowed" : "Not granted")")
    }
}
