import Foundation

/// The next idle activity and when to switch to it.
public struct IdleChoice: Equatable, Sendable {
    public var activity: CompanionState
    public var at: Date

    public init(activity: CompanionState, at: Date) {
        self.activity = activity
        self.at = at
    }
}

public protocol IdleScheduling {
    /// Picks the next idle activity and the moment to switch to it, measured from `now`.
    mutating func next(after now: Date) -> IdleChoice
}

/// Picks a random idle activity every 30-90 seconds. The RNG is injectable; the clock is
/// whatever `now` the caller passes in, so tests never wait.
public struct IdleScheduler: IdleScheduling {
    public static let activities: [CompanionState] = [.waiting, .videogame, .tennis]
    public static let delayRange: ClosedRange<TimeInterval> = 30...90

    private var nextRandom: () -> UInt64

    public init() {
        self.init(rng: SystemRandomNumberGenerator())
    }

    public init<G: RandomNumberGenerator>(rng: G) {
        var generator = rng
        nextRandom = { generator.next() }
    }

    public mutating func next(after now: Date) -> IdleChoice {
        var generator = ClosureGenerator(source: nextRandom)
        let activity = Self.activities.randomElement(using: &generator) ?? .waiting
        let delay = TimeInterval.random(in: Self.delayRange, using: &generator)
        return IdleChoice(activity: activity, at: now.addingTimeInterval(delay))
    }
}

private struct ClosureGenerator: RandomNumberGenerator {
    let source: () -> UInt64

    mutating func next() -> UInt64 { source() }
}
