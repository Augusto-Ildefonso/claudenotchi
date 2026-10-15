import Foundation

/// What the `claudenotchi-hook` executable does: turn a hook payload into an event and hand it to the app.
public enum HookRunner {
    /// Returns whether the event reached the app. Never throws: a hook must not disturb Claude Code
    /// when the app is closed or the payload is unexpected.
    @discardableResult
    public static func run(stdin: Data, socketPath: String, now: Date = Date()) -> Bool {
        guard let event = try? SessionEvent(hookJSON: stdin, receivedAt: now) else { return false }
        do {
            try EventClient.send(event, to: socketPath)
            return true
        } catch {
            return false
        }
    }
}
