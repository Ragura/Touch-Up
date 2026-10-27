import AppKit
import Combine

final class RestartController: ObservableObject {
    @Published private(set) var isRestarting = false
    @Published private(set) var failed = false
    private let prepare: () -> Void
    private let recover: () -> Void
    private let launch: (@escaping (Bool) -> Void) -> Void
    private let terminate: () -> Void

    init(prepare: @escaping () -> Void, recover: @escaping () -> Void,
         launch: @escaping (@escaping (Bool) -> Void) -> Void = RestartController.launchReplacement,
         terminate: @escaping () -> Void = { NSApp.terminate(nil) }) {
        self.prepare = prepare
        self.recover = recover
        self.launch = launch
        self.terminate = terminate
    }

    func restart() {
        guard !isRestarting else { return }
        isRestarting = true
        failed = false
        prepare()
        launch { [weak self] succeeded in
            guard let self = self else { return }
            if succeeded {
                self.terminate()
            } else {
                self.isRestarting = false
                self.failed = true
                self.recover()
            }
        }
    }

    // Completion is delivered on main, matching all controller and UI state changes.
    private static func launchReplacement(completion: @escaping (Bool) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.arguments = ["--show-settings"]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { app, error in
            let succeeded = error == nil && app != nil && app?.processIdentifier != ProcessInfo.processInfo.processIdentifier
            DispatchQueue.main.async { completion(succeeded) }
        }
    }
}
