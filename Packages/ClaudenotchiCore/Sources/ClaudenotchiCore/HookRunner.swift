import Foundation

/// What the `claudenotchi-hook` executable does: turn a hook payload into an event and hand it to the app.
public enum HookRunner {
    public struct Outcome: Equatable, Sendable {
        /// Whether the event reached the app.
        public var delivered: Bool
        /// What to print on stdout for Claude Code (a permission decision), if anything.
        public var output: Data?

        public init(delivered: Bool, output: Data? = nil) {
            self.delivered = delivered
            self.output = output
        }
    }

    /// Never throws: a hook must not disturb Claude Code when the app is closed or the payload is
    /// unexpected. Permission requests block until the user answers in the app; every other event
    /// returns as soon as it is delivered. With no output, Claude Code falls back to its own prompt.
    public static func handle(
        stdin: Data,
        socketPath: String,
        now: Date = Date(),
        ancestry: @Sendable () -> (pids: [Int], tty: String?) = { ProcessAncestry.current() }
    ) -> Outcome {
        guard var event = try? SessionEvent(hookJSON: stdin, receivedAt: now) else { return Outcome(delivered: false) }
        let info = ancestry()
        event.ancestorPIDs = info.pids
        event.tty = info.tty

        do {
            if event.expectsReply {
                let decision = try EventClient.sendAndAwaitReply(event, to: socketPath)
                return Outcome(delivered: true, output: decision?.hookOutput)
            }
            try EventClient.send(event, to: socketPath)
            return Outcome(delivered: true)
        } catch {
            return Outcome(delivered: false)
        }
    }

    /// Convenience for callers that only care whether the event was delivered.
    @discardableResult
    public static func run(stdin: Data, socketPath: String, now: Date = Date()) -> Bool {
        handle(stdin: stdin, socketPath: socketPath, now: now).delivered
    }
}
