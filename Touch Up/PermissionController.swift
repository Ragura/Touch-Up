import AppKit
import Combine
import CoreGraphics
import IOKit

struct PermissionSnapshot: Equatable {
    var accessibility: Bool
    var inputMonitoring: Bool
}

enum TouchPermission: Hashable {
    case accessibility, inputMonitoring
}

// Only this boundary reads or requests OS permissions. Requesting never implies approval.
struct PermissionAccess {
    var read: () -> PermissionSnapshot
    var request: (TouchPermission) -> Void
    var openSettings: (TouchPermission) -> Bool

    static let system = PermissionAccess(
        read: {
            PermissionSnapshot(accessibility: CGPreflightPostEventAccess(),
                               inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted)
        },
        request: { permission in
            switch permission {
            case .accessibility:
                // Request the capability used by CGEventPost. Broad AX trust requests
                // do not provide the sandboxed app's event-posting consent flow.
                _ = CGRequestPostEventAccess()
            case .inputMonitoring:
                _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            }
        },
        openSettings: { permission in
            let pane = permission == .accessibility ? "Privacy_Accessibility" : "Privacy_ListenEvent"
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return false }
            return NSWorkspace.shared.open(url)
        }
    )
}

final class PermissionController: ObservableObject {
    @Published private(set) var snapshot: PermissionSnapshot
    @Published private(set) var inputMonitoringNeedsRestart = false
    @Published private(set) var settingsOpenFailed = false
    @Published private(set) var requestedPermissions: Set<TouchPermission> = []
    private let access: PermissionAccess
    private var sawInputMonitoringUnavailable: Bool
    private var refreshTimer: Timer?

    init(access: PermissionAccess = .system) {
        self.access = access
        let initial = access.read()
        snapshot = initial
        sawInputMonitoringUnavailable = !initial.inputMonitoring
    }

    func refresh() {
        let current = access.read()
        if !current.inputMonitoring { sawInputMonitoringUnavailable = true }
        let needsRestart = current.inputMonitoring && sawInputMonitoringUnavailable
        if inputMonitoringNeedsRestart != needsRestart { inputMonitoringNeedsRestart = needsRestart }
        if snapshot != current { snapshot = current }
    }

    func request(_ permission: TouchPermission) {
        requestedPermissions.insert(permission)
        settingsOpenFailed = false
        access.request(permission)
        refresh()
        // Let the system permission dialog handle its own navigation. Opening
        // Settings here can race that dialog and show the list before registration.
    }

    func openSettings(_ permission: TouchPermission) {
        settingsOpenFailed = !access.openSettings(permission)
    }

    // Poll only while the settings window is open, including while System Settings is active.
    func startMonitoring() {
        refresh()
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    deinit { refreshTimer?.invalidate() }
}
