import AppKit

@main
struct PermissionTests {
    static func main() {
        var current = PermissionSnapshot(accessibility: false, inputMonitoring: false)
        var requested: [TouchPermission] = []
        var opened: [TouchPermission] = []
        var openSucceeds = true
        let access = PermissionAccess(read: { current }, request: { requested.append($0) }, openSettings: { opened.append($0); return openSucceeds })
        let permissions = PermissionController(access: access)
        precondition(permissions.snapshot == current)
        precondition(requested.isEmpty && opened.isEmpty) // Passive refresh never prompts.
        permissions.request(.accessibility)
        precondition(!permissions.snapshot.accessibility)
        precondition(requested == [.accessibility] && opened.isEmpty)
        precondition(permissions.requestedPermissions.contains(.accessibility))
        permissions.request(.inputMonitoring)
        precondition(!permissions.snapshot.inputMonitoring)
        precondition(requested == [.accessibility, .inputMonitoring] && opened.isEmpty)
        permissions.openSettings(.accessibility)
        permissions.openSettings(.inputMonitoring)
        precondition(opened == [.accessibility, .inputMonitoring])
        current.accessibility = true
        permissions.refresh()
        precondition(permissions.snapshot.accessibility && !permissions.snapshot.inputMonitoring)
        precondition(!permissions.inputMonitoringNeedsRestart)
        current.inputMonitoring = true
        permissions.refresh()
        precondition(permissions.snapshot == current && permissions.inputMonitoringNeedsRestart)
        current.accessibility = false
        permissions.refresh()
        precondition(!permissions.snapshot.accessibility && permissions.snapshot.inputMonitoring)
        current.inputMonitoring = false
        permissions.refresh()
        precondition(!permissions.snapshot.inputMonitoring && !permissions.inputMonitoringNeedsRestart)
        openSucceeds = false
        permissions.openSettings(.accessibility)
        precondition(permissions.settingsOpenFailed && !permissions.snapshot.accessibility)
        openSucceeds = true
        permissions.openSettings(.accessibility)
        precondition(!permissions.settingsOpenFailed)
        current = PermissionSnapshot(accessibility: true, inputMonitoring: true)
        let fresh = PermissionController(access: access)
        precondition(!fresh.inputMonitoringNeedsRestart) // Granted at process launch needs no restart.
        // Window monitoring observes external changes without button presses or app activation.
        permissions.refresh()
        permissions.startMonitoring()
        permissions.startMonitoring()
        current.accessibility = false
        let deadline = Date().addingTimeInterval(3)
        while permissions.snapshot.accessibility && Date() < deadline {
            RunLoop.main.run(mode: .default, before: deadline)
        }
        precondition(!permissions.snapshot.accessibility)
        permissions.stopMonitoring()
        permissions.stopMonitoring()
        // The run loop must not retain a controller after its window/model goes away.
        weak var released: PermissionController?
        autoreleasepool {
            let temporary = PermissionController(access: access)
            temporary.startMonitoring()
            released = temporary
        }
        precondition(released == nil)
        print("PASS: independent permission grants/revocations, non-optimistic requests, restart guidance, settings failure, live polling and teardown.")
    }
}
