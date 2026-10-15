/// When the pill is on screen: only while Claude Code is open (unless the user wants it always there).
public enum PillVisibility {
    public static func isVisible(hideWhenClosed: Bool, sessionsOpen: Bool, state: CompanionState) -> Bool {
        guard hideWhenClosed else { return true }
        // Let the "done" celebration finish after the last session ends, and never hide a pending request.
        return sessionsOpen || state == .done || state == .needsInput
    }
}
