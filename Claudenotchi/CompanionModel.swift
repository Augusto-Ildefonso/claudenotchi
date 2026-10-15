import ClaudenotchiCore
import Foundation
import Observation
import OSLog

/// Connects the hook event socket to the state machine and publishes what the pill should show.
@Observable
final class CompanionModel {
    private(set) var state: CompanionState = .waiting
    /// When `state` began; sprite animations restart from here.
    private(set) var stateSince = Date()
    /// Set by the window controller once the mouse has rested on the pill for the chosen delay.
    var hoverExpanded = false
    /// Permission prompts waiting for an answer, oldest first.
    private(set) var prompts = PromptQueue()

    private var lastCwd: String?
    private var lastMessage: String?
    @ObservationIgnored private var lastAncestors: [Int] = []
    @ObservationIgnored private var lastTTY: String?

    @ObservationIgnored private var machine: StateMachine
    @ObservationIgnored private let server: EventServer
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private let log = Logger(subsystem: "dev.claudenotchi.Claudenotchi", category: "model")

    init(socketPath: String = SocketPath.default()) {
        machine = StateMachine(now: Date(), scheduler: IdleScheduler(activities: SpriteLibrary.shared.idleActivities))
        server = EventServer(path: socketPath)
    }

    // MARK: What to show

    /// A request for the user always shows the attention panel; hovering shows the smaller one.
    var presentation: PillPresentation {
        if state == .needsInput { return .attention }
        return hoverExpanded ? .hover : .collapsed
    }

    var currentPrompt: PendingPrompt? { prompts.current }

    /// Approve / Deny only exist while the shown prompt is one the notch can answer. A question or a plan
    /// (Claude Code fires the permission hook for them too) can only be answered in the terminal.
    var hasAttentionButtons: Bool { prompts.current?.canAnswerFromNotch ?? false }

    /// Second line of the expanded pill: what Claude is asking, or the project folder.
    var detail: String {
        if state == .needsInput { return attentionMessage }
        if let cwd = lastCwd { return PathDisplay.abbreviated(cwd, home: NSHomeDirectory()) }
        return "No session yet"
    }

    /// What Claude wants, for the attention panel.
    var attentionMessage: String {
        if let prompt = prompts.current { return prompt.message }
        if let message = lastMessage, !message.isEmpty { return message }
        return "Claude is waiting for you"
    }

    /// 1 or 2: lines the request text needs, which sets the attention panel's height.
    var attentionLines: Int { AttentionLayout.lineCount(for: attentionMessage) }

    // MARK: Lifecycle

    func start() {
        do {
            try server.start()
        } catch {
            log.error("Could not start the event server: \(String(describing: error))")
        }

        tasks.append(Task { [server] in
            for await event in server.events { handle(event) }
        })
        tasks.append(Task { [server] in
            // The helper hung up before we answered: the user answered in the terminal.
            for await id in server.cancellations {
                log.info("prompt \(id.prefix(8), privacy: .public) closed: the helper hung up")
                prompts.remove(id: id)
                // Esc on a dialog sends no hook event; Claude Code only kills the waiting hook. With nothing
                // else waiting, the user is no longer being asked for anything.
                if prompts.isEmpty {
                    machine.promptCancelled(at: Date())
                    publish()
                }
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

    // MARK: Answering

    func approve() { answer(.allow) }

    func deny() { answer(.deny(message: "Denied from Claudenotchi")) }

    private func answer(_ decision: PermissionDecision) {
        guard let prompt = prompts.current, prompt.canAnswerFromNotch else { return }
        prompts.remove(id: prompt.id)
        let delivered = server.reply(to: prompt.id, with: decision)
        log.info("prompt \(prompt.id.prefix(8), privacy: .public) answered in the notch: \(String(describing: decision), privacy: .public), delivered: \(delivered)")
        if prompts.isEmpty {
            // Claude carries on right away; do not wait for its next hook to say so.
            machine.promptAnswered(at: Date())
            publish()
        }
    }

    /// Brings the terminal running this Claude Code session to the front.
    func focusTerminal() {
        log.info("focus requested; prompt: \(self.prompts.current != nil, privacy: .public), ancestors: \(self.prompts.current?.ancestorPIDs ?? self.lastAncestors, privacy: .public)")
        if let prompt = prompts.current {
            TerminalFocuser.focus(ancestorPIDs: prompt.ancestorPIDs, tty: prompt.tty)
        } else {
            TerminalFocuser.focus(ancestorPIDs: lastAncestors, tty: lastTTY)
        }
    }

    // MARK: Events

    private func handle(_ event: SessionEvent) {
        let before = state
        // Later activity in a session means its open prompts are over (answered in the terminal, or
        // Claude moved on); release their helpers so Claude Code shows its own prompt or continues.
        for id in prompts.eventArrived(event) {
            log.info("prompt \(id.prefix(8), privacy: .public) released: later \(event.type.rawValue, privacy: .public) event")
            server.cancel(requestID: id)
        }
        if event.type == .permissionRequest {
            log.info("permission request: \(event.message ?? "-", privacy: .public)")
        }

        let promptsBefore = prompts.count
        if let prompt = PendingPrompt(event: event) { prompts.add(prompt) }
        remember(event)

        machine.handle(event)
        publish()

        // A second prompt while one is already showing gets its own chime.
        if before == .needsInput, state == .needsInput, prompts.count > promptsBefore {
            SoundPlayer.shared.play(.needsInput)
        }
    }

    private func remember(_ event: SessionEvent) {
        if let cwd = event.cwd, !cwd.isEmpty { lastCwd = cwd }
        if event.type == .notification || event.type == .permissionRequest { lastMessage = event.message }
        if !event.ancestorPIDs.isEmpty {
            lastAncestors = event.ancestorPIDs
            lastTTY = event.tty
        }
    }

    private func publish() {
        guard state != machine.state else { return }
        let old = state
        state = machine.state
        stateSince = machine.stateSince
        log.debug("state -> \(self.state.rawValue, privacy: .public)")
        if let cue = SoundCue.cue(from: old, to: state) { SoundPlayer.shared.play(cue) }
    }
}
