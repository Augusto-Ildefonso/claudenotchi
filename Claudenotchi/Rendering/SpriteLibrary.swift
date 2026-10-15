import ClaudenotchiCore
import CoreGraphics
import Foundation
import OSLog

/// One state's animation: every frame already cropped, plus its speed.
struct SpriteClip {
    let frames: [CGImage]
    let fps: Double
}

/// Loads sprite strips and the manifest from the app bundle and caches the cropped frames.
final class SpriteLibrary {
    static let shared = SpriteLibrary()

    /// Used when `manifest.json` is missing or has no entry for a state.
    private static let fallbackFPS = 6.0

    private let log = Logger(subsystem: "dev.claudenotchi.Claudenotchi", category: "sprites")
    private lazy var manifest: SpriteManifest? = Self.loadManifest(log: log)
    private var clips: [CompanionState: SpriteClip] = [:]

    func clip(for state: CompanionState) -> SpriteClip? {
        if let cached = clips[state] { return cached }
        guard let sheet = SpriteSheet.load(state: state.spriteName, size: 16) else {
            log.error("Missing sprite strip for \(state.rawValue)")
            return nil
        }
        let entry = manifest?.entry(for: state)
        let count = min(entry?.frames ?? sheet.frameCount, sheet.frameCount)
        let frames = (0..<count).compactMap { sheet.frame($0) }
        guard !frames.isEmpty else { return nil }
        let clip = SpriteClip(frames: frames, fps: entry?.fps ?? Self.fallbackFPS)
        clips[state] = clip
        return clip
    }

    private static func loadManifest(log: Logger) -> SpriteManifest? {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json")
                ?? Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "Sprites") else {
            log.error("manifest.json not found in the app bundle")
            return nil
        }
        do {
            return try SpriteManifest(json: Data(contentsOf: url))
        } catch {
            log.error("manifest.json is invalid: \(String(describing: error))")
            return nil
        }
    }
}
