import AppKit
import ClaudenotchiCore
import OSLog

/// Plays the bundled 8-bit chimes, unless the user turned sounds off in the menu.
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let log = Logger(subsystem: "dev.claudenotchi.Claudenotchi", category: "sound")
    private var sounds: [SoundCue: NSSound] = [:]

    func play(_ cue: SoundCue) {
        guard AppSettings.soundsEnabled() else { return }
        guard let sound = sound(for: cue) else { return }
        sound.stop() // restart if it is still playing from a moment ago
        let started = sound.play()
        log.debug("play \(cue.fileName, privacy: .public): \(started ? "started" : "failed", privacy: .public)")
    }

    private func sound(for cue: SoundCue) -> NSSound? {
        if let cached = sounds[cue] { return cached }
        guard let url = Bundle.main.url(forResource: cue.fileName, withExtension: "wav")
                ?? Bundle.main.url(forResource: cue.fileName, withExtension: "wav", subdirectory: "Sounds"),
              let sound = NSSound(contentsOf: url, byReference: false) else {
            log.error("Missing sound \(cue.fileName, privacy: .public).wav")
            return nil
        }
        sounds[cue] = sound
        return sound
    }
}
