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

    private struct Key: Hashable {
        let state: CompanionState
        let size: Int
    }

    private let log = Logger(subsystem: "dev.claudenotchi.Claudenotchi", category: "sprites")
    private lazy var manifest: SpriteManifest? = Self.loadManifest(log: log)
    private var clips: [Key: SpriteClip] = [:]

    /// - Parameter size: 16 for the collapsed pill, 32 for the expanded view. A state without 32px art
    ///   falls back to its 16px frames (the caller scales them with nearest-neighbor).
    func clip(for state: CompanionState, size: Int = 16) -> SpriteClip? {
        let key = Key(state: state, size: size)
        if let cached = clips[key] { return cached }

        let entry = manifest?.entry(for: state)
        let wants32 = size >= 32 && entry?.size32 != nil
        let stripSize = wants32 ? 32 : 16
        guard let sheet = SpriteSheet.load(state: state.spriteName, size: stripSize) else {
            log.error("Missing \(stripSize)px sprite strip for \(state.rawValue)")
            return nil
        }
        let declared = wants32 ? (entry?.frames32 ?? sheet.frameCount) : (entry?.frames ?? sheet.frameCount)
        let count = min(declared, sheet.frameCount)
        let frames = (0..<count).compactMap { sheet.frame($0) }
        guard !frames.isEmpty else { return nil }

        let clip = SpriteClip(frames: frames, fps: entry?.fps ?? Self.fallbackFPS)
        clips[key] = clip
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
