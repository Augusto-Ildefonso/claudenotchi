import AppKit
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

    /// True while at least one Claude Code session is open (see `SessionRegistry`).
    private(set) var sessionsOpen = false

    /// What the current session has used so far (context, cost); nil until a transcript has been read.
    private(set) var usage: UsageSnapshot?

    private var lastCwd: String?
    private var lastMessage: String?
    @ObservationIgnored private var lastAncestors: [Int] = []
    @ObservationIgnored private var transcriptPath: String?
    @ObservationIgnored private var trackers: [String: UsageTracker] = [:]
    @ObservationIgnored private var usageRefreshRunning = false
    @ObservationIgnored private var usageRefreshQueued = false
    @ObservationIgnored private var lastTTY: String?

    @ObservationIgnored private var registry = SessionRegistry()
    @ObservationIgnored private var lastPrune = Date()
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

    /// Whether the pill is on screen at all: only while Claude Code is open, unless the user turned that off.
    var isPillVisible: Bool {
        PillVisibility.isVisible(hideWhenClosed: AppSettings.hideWhenClosed(), sessionsOpen: sessionsOpen, state: state)
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

    /// Returns false when another copy of the app already serves the hook socket; this one should quit rather
    /// than take it over.
    @discardableResult
    func start() -> Bool {
        do {
            try server.start()
        } catch EventServer.Failure.alreadyRunning {
            log.error("Another Claudenotchi is already running; leaving its socket alone")
            return false
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
                let now = Date()
                machine.tick(now: now)
                if now.timeIntervalSince(lastPrune) >= 2 {
                    lastPrune = now
                    // Closing the terminal or killing Claude sends no SessionEnd; its process being gone says it.
                    registry.prune(now: now) { ProcessAncestry.isRunning($0) }
                    updateSessionsOpen()
                }
                publish()
            }
        })
        return true
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        server.stop()
    }

    // MARK: Usage

    /// Re-reads what was added to the session's transcript. Off the main thread; calls that arrive while a
    /// read is running collapse into one more read afterwards.
    func refreshUsage() {
        guard let path = transcriptPath else { return }
        guard !usageRefreshRunning else {
            usageRefreshQueued = true
            return
        }
        usageRefreshRunning = true
        let tracker = trackers[path] ?? UsageTracker(path: path)
        trackers = [path: tracker] // only the current session is worth keeping
        Task {
            let snapshot = await Task.detached(priority: .utility) { tracker.refresh() }.value
            usage = snapshot.messageCount > 0 ? snapshot : nil
            usageRefreshRunning = false
            if usageRefreshQueued {
                usageRefreshQueued = false
                refreshUsage()
            }
        }
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
        registry.handle(
            event,
            claudePID: ProcessAncestry.claudePID(in: event.ancestorPIDs),
            interactive: Self.isInTerminal(event)
        )
        updateSessionsOpen()

        machine.handle(event)
        publish()

        // Usage only changes when Claude finishes a step; reading on these events keeps it current.
        switch event.type {
        case .sessionStart, .userPromptSubmit, .postToolUse, .stop: refreshUsage()
        default: break
        }

        // A second prompt while one is already showing gets its own chime.
        if before == .needsInput, state == .needsInput, prompts.count > promptsBefore {
            SoundPlayer.shared.play(.needsInput)
        }
    }

    /// Whether the event comes from a session the user can see in a terminal (a terminal app or multiplexer is
    /// above it). nil when the event carries no process chain, so it says nothing either way.
    private static func isInTerminal(_ event: SessionEvent) -> Bool? {
        guard !event.ancestorPIDs.isEmpty else { return nil }
        return ProcessAncestry.isAttachedToTerminal(ancestors: event.ancestorPIDs) { pid in
            NSRunningApplication(processIdentifier: pid_t(pid))?.activationPolicy == .regular
        }
    }

    /// The pill is about Claude Code in a terminal; a background session (a daemon's, the desktop app's) runs
    /// the same hooks but does not keep it on screen.
    private func updateSessionsOpen() {
        let open = registry.hasInteractiveSession
        if open != sessionsOpen {
            sessionsOpen = open
            log.info("terminal sessions open: \(open, privacy: .public) (sessions of any kind: \(self.registry.count, privacy: .public))")
        }
    }

    private func remember(_ event: SessionEvent) {
        if let cwd = event.cwd, !cwd.isEmpty { lastCwd = cwd }
        if let path = event.transcriptPath, !path.isEmpty {
            if path != transcriptPath { usage = nil } // a different session: do not show the old numbers
            transcriptPath = path
        }
        // Only real requests; "Claude is waiting for your input" (idle_prompt) is a reminder, not something to show.
        let isRequest = event.type == .permissionRequest
            || (event.type == .notification && [nil, "permission_prompt", "elicitation_dialog"].contains(event.notificationType))
        if isRequest { lastMessage = event.message }
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
