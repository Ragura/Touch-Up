import AppKit
import SwiftUI

// Render the actual compact permission component with fake access. No OS prompts or USB access.
@main
struct PermissionPreview {
    static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for name in ["missing", "control-missing", "requested", "allowed", "restart"] {
            var state = PermissionSnapshot(accessibility: name != "missing" && name != "control-missing" && name != "requested", inputMonitoring: name == "allowed" || name == "control-missing" || name == "requested")
            let controller = PermissionController(access: PermissionAccess(read: { state }, request: { _ in }, openSettings: { _ in true }))
            if name == "requested" { controller.request(.accessibility) }
            if name == "restart" { state.inputMonitoring = true; controller.refresh() }
            let root = Form {
                Section("Permissions") { PermissionStatusView(permissions: controller, restarter: RestartController(prepare: {}, recover: {}, launch: { _ in }, terminate: {})) }
                Section { Toggle("Control Mouse with Touch", isOn: .constant(true)) }
            }.formStyle(.grouped).frame(width: 400, height: 260)
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 260), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: 400, height: 260)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
            try png.write(to: output.appendingPathComponent("permissions-\(name).png"))
            window.orderOut(nil)
        }
    }
}
