import ClaudenotchiCore

/// Loads and caches the 16px sprite strip for each state.
final class SpriteLibrary {
    static let shared = SpriteLibrary()

    private var sheets: [CompanionState: SpriteSheet] = [:]

    func sheet(for state: CompanionState) -> SpriteSheet? {
        if let cached = sheets[state] { return cached }
        guard let loaded = SpriteSheet.load(state: state.spriteName, size: 16) else { return nil }
        sheets[state] = loaded
        return loaded
    }
}
