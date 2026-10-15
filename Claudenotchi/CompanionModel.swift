import ClaudenotchiCore
import Observation
import OSLog

/// Connects the hook event socket to the state machine and publishes the mascot's current state.
@Observable
final class CompanionModel {
    private(set) var state: CompanionState = .waiting

    @ObservationIgnored private var machine = StateMachine(now: Date())
    @ObservationIgnored private let server: EventServer
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private let log = Logger(subsystem: "dev.claudenotchi.Claudenotchi", category: "model")

    init(socketPath: String = SocketPath.default()) {
        server = EventServer(path: socketPath)
    }

    func start() {
        do {
            try server.start()
        } catch {
            log.error("Could not start the event server: \(String(describing: error))")
        }

        tasks.append(Task { [server] in
            for await event in server.events {
                machine.handle(event)
                publish()
            }
        })
        tasks.append(Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                machine.tick(now: Date())
                publish()
            }
        })
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        server.stop()
    }

    private func publish() {
        if state != machine.state {
            log.debug("state -> \(self.machine.state.rawValue)")
            state = machine.state
        }
    }
}
