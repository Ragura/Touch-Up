import Foundation

@main
struct RestartTests {
    static func main() {
        var events: [String] = []
        var pending: ((Bool) -> Void)?
        let controller = RestartController(
            prepare: { events.append("save-and-stop") },
            recover: { events.append("resume") },
            launch: { completion in events.append("launch"); pending = completion },
            terminate: { events.append("terminate") })
        controller.restart()
        controller.restart()
        precondition(events == ["save-and-stop", "launch"])
        precondition(controller.isRestarting && !controller.failed)
        pending?(false)
        precondition(events == ["save-and-stop", "launch", "resume"])
        precondition(!controller.isRestarting && controller.failed)
        controller.restart()
        precondition(controller.isRestarting && !controller.failed)
        pending?(true)
        precondition(events == ["save-and-stop", "launch", "resume", "save-and-stop", "launch", "terminate"])
        precondition(controller.isRestarting) // Suppress duplicate saves during termination.
        print("PASS: restart saves/stops before launch, prevents duplicate launches, recovers on failure and terminates only on success.")
    }
}
