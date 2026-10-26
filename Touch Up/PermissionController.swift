import AppKit
import Combine
import IOKit

struct PermissionSnapshot: Equatable {
    var accessibility: Bool
    var inputMonitoring: Bool
}

enum TouchPermission {
    case accessibility, inputMonitoring
}

// Only this boundary reads or requests OS permissions. Requesting never implies approval.
struct PermissionAccess {
    var read: () -> PermissionSnapshot
    var request: (TouchPermission) -> Void
    var openSettings: (TouchPermission) -> Bool

    static let system = PermissionAccess(
        read: {
            PermissionSnapshot(accessibility: AXIsProcessTrusted(),
                               inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted)
        },
        request: { permission in
            switch permission {
            case .accessibility:
                let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
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
        access.request(permission)
        refresh()
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
