/// What the mascot is doing.
public enum CompanionState: String, Sendable, CaseIterable {
    case waiting, thinking, coding, reading, bash, web
    case needsInput, error, done
    case videogame, tennis, sleeping

    /// Name of the sprite strip in `Sprites/manifest.json`.
    public var spriteName: String {
        switch self {
        case .needsInput: "alert"
        case .done: "celebrating"
        default: rawValue
        }
    }
}
