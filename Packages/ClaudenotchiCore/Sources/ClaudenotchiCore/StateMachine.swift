import Foundation

/// Pure reducer: hook events and clock ticks in, mascot state out. No timers of its own;
/// the caller drives `tick(now:)`, so tests use a fake clock.
public struct StateMachine {
    public static let errorDuration: TimeInterval = 3
    public static let doneDuration: TimeInterval = 5
    public static let sleepAfter: TimeInterval = 300

    public private(set) var state: CompanionState = .waiting
    public private(set) var stateSince: Date

    private var lastActivity: Date
    private var scheduler: any IdleScheduling
    private var idleBase: Date
    private var nextIdle: IdleChoice?

    public init(now: Date, scheduler: any IdleScheduling = IdleScheduler()) {
        self.stateSince = now
        self.lastActivity = now
        self.idleBase = now
        self.scheduler = scheduler
    }

    /// Maps a Claude Code tool name to the state shown while it runs.
    public static func state(forTool tool: String?) -> CompanionState {
        switch tool {
        case "Edit", "Write", "MultiEdit", "NotebookEdit": .coding
        case "Read", "Grep", "Glob": .reading
        case "Bash": .bash
        case "WebSearch", "WebFetch": .web
        default: .thinking
        }
    }

    public mutating func handle(_ event: SessionEvent) {
        let now = event.timestamp
        // A reminder such as `idle_prompt` (sent 60 s after Claude finished) is not activity and not a request.
        if event.type == .notification, !shouldAskForInput(event) { return }
        lastActivity = now
        switch event.type {
        case .userPromptSubmit:
            transition(to: .thinking, at: now)
        case .notification, .permissionRequest:
            transition(to: .needsInput, at: now)
        case .stop:
            transition(to: .done, at: now)
        case .sessionEnd:
            // A finished session sends SessionEnd right after Stop; let the celebration run its course.
            if state != .done { transition(to: .waiting, at: now) }
        case .sessionStart:
            if isIdle || state == .sleeping { transition(to: .waiting, at: now) }
        case .postToolUseFailure:
            // A tool the user interrupted is not an error worth showing.
            transition(to: event.isInterrupt ? .thinking : .error, at: now)
        case .postToolUse:
            if !errorIsStillShowing(at: now) { transition(to: .thinking, at: now) }
        case .preToolUse:
            // After a denied permission prompt Claude Code sends no PostToolUse, only the next
            // PreToolUse, so a new tool starting also means the earlier prompt was resolved.
            if !errorIsStillShowing(at: now) {
                transition(to: Self.state(forTool: event.tool), at: now)
            }
        case .unknown:
            if state == .sleeping { transition(to: .waiting, at: now) }
        }
    }

    /// The user answered a permission prompt in the app: Claude goes on working, so show it right away
    /// instead of waiting for the next hook event.
    public mutating func promptAnswered(at now: Date) {
        guard state == .needsInput else { return }
        lastActivity = now
        transition(to: .thinking, at: now)
    }

    /// The prompt went away with no answer from the app and no hook event: the user cancelled the dialog in
    /// the terminal (Esc), which Claude Code reports only by killing the waiting hook.
    public mutating func promptCancelled(at now: Date) {
        guard state == .needsInput else { return }
        lastActivity = now
        transition(to: .waiting, at: now)
    }

    public mutating func tick(now: Date) {
        switch state {
        case .done:
            if now.timeIntervalSince(stateSince) >= Self.doneDuration { transition(to: .waiting, at: now) }
        case .error:
            if now.timeIntervalSince(stateSince) >= Self.errorDuration { transition(to: .thinking, at: now) }
        case .waiting, .videogame, .tennis:
            if now.timeIntervalSince(lastActivity) >= Self.sleepAfter {
                transition(to: .sleeping, at: now)
                return
            }
            if nextIdle == nil { nextIdle = scheduler.next(after: idleBase) }
            if let choice = nextIdle, now >= choice.at {
                if choice.activity != state {
                    state = choice.activity
                    stateSince = now
                }
                idleBase = now
                nextIdle = nil
            }
        case .thinking, .coding, .reading, .bash, .web, .needsInput, .sleeping:
            break
        }
    }

    /// Whether a notification is Claude asking the user for something right now. Claude Code sends the permission
    /// notification about 6 s after the dialog opened, which can be after the work already went on or finished,
    /// and a prompt can only exist while a turn is running. The real `PermissionRequest` hook is the primary
    /// signal; the notification only matters for a turn in progress.
    private func shouldAskForInput(_ event: SessionEvent) -> Bool {
        switch event.notificationType {
        case nil, "permission_prompt", "elicitation_dialog": break
        default: return false // idle_prompt, auth_success, and types not known yet
        }
        switch state {
        case .waiting, .videogame, .tennis, .sleeping, .done: return false
        case .thinking, .coding, .reading, .bash, .web, .needsInput, .error: return true
        }
    }

    private var isIdle: Bool { state.isIdleActivity }

    private func errorIsStillShowing(at now: Date) -> Bool {
        state == .error && now.timeIntervalSince(stateSince) < Self.errorDuration
    }

    private mutating func transition(to new: CompanionState, at now: Date) {
        state = new
        stateSince = now
        if new == .waiting {
            idleBase = now
            nextIdle = nil
        }
    }
}
