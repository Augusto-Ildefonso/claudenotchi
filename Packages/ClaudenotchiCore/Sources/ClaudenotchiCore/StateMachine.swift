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

    private var isIdle: Bool {
        state == .waiting || state == .videogame || state == .tennis
    }

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
