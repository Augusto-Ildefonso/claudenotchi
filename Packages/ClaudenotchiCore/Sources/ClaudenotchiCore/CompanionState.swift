/// What the mascot is doing.
public enum CompanionState: String, Sendable, CaseIterable {
    case waiting, thinking, coding, reading, bash, web
    case needsInput, error, done
    case videogame, tennis, sleeping

    /// Short status line for the expanded pill.
    public var title: String {
        switch self {
        case .waiting: "Waiting"
        case .thinking: "Thinking…"
        case .coding: "Editing files"
        case .reading: "Reading"
        case .bash: "Running a command"
        case .web: "Searching the web"
        case .needsInput: "Needs your input"
        case .error: "Something failed"
        case .done: "Done"
        case .videogame, .tennis: "Taking a break"
        case .sleeping: "Sleeping"
        }
    }

    /// Name of the sprite strip in `Sprites/manifest.json`.
    public var spriteName: String {
        switch self {
        case .needsInput: "alert"
        case .done: "celebrating"
        default: rawValue
        }
    }
}
