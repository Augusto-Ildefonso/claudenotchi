import Foundation

/// User preferences, stored in `UserDefaults`. Read on use, so changes apply immediately.
enum AppSettings {
    /// Seconds the mouse must rest on the pill before it expands. Negative means "never".
    static let hoverDelayKey = "hoverDelay"
    static let defaultHoverDelay = 0.5

    static let hoverDelayOptions: [(label: String, seconds: Double)] = [
        ("Off", -1),
        ("Instantly", 0),
        ("0.25 seconds", 0.25),
        ("0.5 seconds", 0.5),
        ("1 second", 1),
        ("1.5 seconds", 1.5),
        ("2 seconds", 2),
        ("3 seconds", 3),
    ]

    /// Size in points of the mascot in the collapsed pill. 16, 24 and 32 are whole multiples of the 16px art
    /// at 2x (2, 3 and 4 screen pixels per art pixel), so the pixels stay sharp.
    static let mascotSizeKey = "mascotSize"
    static let defaultMascotSize = 24.0
    static let mascotSizeOptions: [(label: String, points: Double)] = [
        ("Small", 16),
        ("Medium", 24),
        ("Large", 32),
    ]

    /// Whether the 8-bit chimes play (needs input, done). On by default.
    static let soundsEnabledKey = "soundsEnabled"

    static func soundsEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: soundsEnabledKey) == nil ? true : defaults.bool(forKey: soundsEnabledKey)
    }

    static func hoverDelay(_ defaults: UserDefaults = .standard) -> Double {
        defaults.object(forKey: hoverDelayKey) == nil ? defaultHoverDelay : defaults.double(forKey: hoverDelayKey)
    }
}
