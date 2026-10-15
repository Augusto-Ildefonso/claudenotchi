/// Short sounds the app can play.
public enum SoundCue: String, Sendable, CaseIterable {
    case needsInput
    case done

    /// File name (without extension) in `Claudenotchi/Sounds/`.
    public var fileName: String {
        switch self {
        case .needsInput: "needs-input"
        case .done: "done"
        }
    }

    /// The sound for a change of state, or nil when the change is silent. Only entering
    /// `needsInput` and `done` are worth interrupting you for.
    public static func cue(from old: CompanionState, to new: CompanionState) -> SoundCue? {
        guard old != new else { return nil }
        switch new {
        case .needsInput: return .needsInput
        case .done: return .done
        default: return nil
        }
    }
}
