import Foundation

/// A permission prompt waiting for the user, answerable through `EventServer.reply(to:with:)`.
public struct PendingPrompt: Equatable, Sendable, Identifiable {
    /// The request id the server assigned.
    public let id: String
    public let sessionID: String
    public let tool: String?
    /// One line describing the request, e.g. `Bash: xcodebuild -scheme App build`.
    public let message: String
    public let cwd: String?
    public let ancestorPIDs: [Int]
    public let tty: String?

    public init(id: String, sessionID: String, tool: String?, message: String, cwd: String?, ancestorPIDs: [Int], tty: String?) {
        self.id = id
        self.sessionID = sessionID
        self.tool = tool
        self.message = message
        self.cwd = cwd
        self.ancestorPIDs = ancestorPIDs
        self.tty = tty
    }

    /// False for questions and plans: Claude Code fires the permission hook for them, but only the terminal can
    /// answer. The notch still shows them, without buttons, and watches for the dialog being cancelled.
    public var canAnswerFromNotch: Bool { !ToolSummary.needsTerminal(tool: tool) }

    /// Nil unless the event carries the request id the server assigned.
    public init?(event: SessionEvent) {
        guard let id = event.requestID else { return nil }
        self.init(
            id: id, sessionID: event.sessionID, tool: event.tool,
            message: event.message ?? "Permission requested",
            cwd: event.cwd, ancestorPIDs: event.ancestorPIDs, tty: event.tty
        )
    }
}

/// Permission prompts in arrival order; the oldest is the one shown.
public struct PromptQueue: Equatable, Sendable {
    public private(set) var prompts: [PendingPrompt] = []

    public init() {}

    public var current: PendingPrompt? { prompts.first }
    public var isEmpty: Bool { prompts.isEmpty }
    public var count: Int { prompts.count }

    public mutating func add(_ prompt: PendingPrompt) {
        guard !prompts.contains(where: { $0.id == prompt.id }) else { return }
        prompts.append(prompt)
    }

    @discardableResult
    public mutating func remove(id: String) -> PendingPrompt? {
        guard let index = prompts.firstIndex(where: { $0.id == id }) else { return nil }
        return prompts.remove(at: index)
    }

    /// Drops the session's prompts when its next event shows they are over: the user answered in the
    /// terminal, or Claude moved on. Returns the ids that were dropped, so their helpers can be released.
    public mutating func eventArrived(_ event: SessionEvent) -> [String] {
        switch event.type {
        case .postToolUse, .postToolUseFailure, .preToolUse, .stop, .userPromptSubmit, .sessionEnd:
            let resolved = prompts.filter { $0.sessionID == event.sessionID }.map(\.id)
            prompts.removeAll { $0.sessionID == event.sessionID }
            return resolved
        case .notification, .sessionStart, .permissionRequest, .unknown:
            return []
        }
    }
}
