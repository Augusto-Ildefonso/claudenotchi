import ClaudenotchiCore
import Foundation
import Observation
import OSLog

/// Connects the hook event socket to the state machine and publishes the mascot's current state.
@Observable
final class CompanionModel {
    private(set) var state: CompanionState = .waiting
    /// When `state` began; sprite animations restart from here.
    private(set) var stateSince = Date()
    /// Whether the pill is showing its hover-expanded layout (set by the window controller).
    var isExpanded = false

    private var lastCwd: String?
    private var lastMessage: String?

    @ObservationIgnored private var machine = StateMachine(now: Date())
    @ObservationIgnored private let server: EventServer
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private let log = Logger(subsystem: "dev.claudenotchi.Claudenotchi", category: "model")

    init(socketPath: String = SocketPath.default()) {
        server = EventServer(path: socketPath)
    }

    /// Second line of the expanded pill: what Claude is asking, or the project folder.
    var detail: String {
        if state == .needsInput, let message = lastMessage, !message.isEmpty { return message }
        if let cwd = lastCwd { return PathDisplay.abbreviated(cwd, home: NSHomeDirectory()) }
        return "No session yet"
    }

    func start() {
        do {
            try server.start()
        } catch {
            log.error("Could not start the event server: \(String(describing: error))")
        }

        tasks.append(Task { [server] in
            for await event in server.events {
                remember(event)
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

    private func remember(_ event: SessionEvent) {
        if let cwd = event.cwd, !cwd.isEmpty { lastCwd = cwd }
        if event.type == .notification || event.type == .permissionRequest { lastMessage = event.message }
    }

    private func publish() {
        if state != machine.state {
            log.debug("state -> \(self.machine.state.rawValue, privacy: .public)")
            state = machine.state
            stateSince = machine.stateSince
        }
    }
}
