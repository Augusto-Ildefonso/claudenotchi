import Foundation
@testable import ClaudenotchiCore

/// Deterministic RNG (SplitMix64) so scheduler tests are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Idle scheduler that replays a fixed script, for state machine tests.
struct ScriptedIdle: IdleScheduling {
    var script: [(activity: CompanionState, delay: TimeInterval)]
    private(set) var asked: [Date] = []

    init(_ script: [(CompanionState, TimeInterval)]) {
        self.script = script.map { (activity: $0.0, delay: $0.1) }
    }

    mutating func next(after now: Date) -> IdleChoice {
        asked.append(now)
        let item = script.isEmpty ? (activity: CompanionState.waiting, delay: 60) : script.removeFirst()
        return IdleChoice(activity: item.activity, at: now.addingTimeInterval(item.delay))
    }
}

func event(_ type: SessionEvent.EventType, tool: String? = nil, at time: Date, session: String = "s1") -> SessionEvent {
    SessionEvent(sessionID: session, type: type, tool: tool, timestamp: time)
}
