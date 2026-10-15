import Foundation
import Testing
@testable import ClaudenotchiCore

@Suite struct IdleSchedulerTests {
    let start = Date(timeIntervalSince1970: 10_000)

    @Test func delayIsBetween30And90Seconds() {
        var scheduler = IdleScheduler(rng: SeededGenerator(seed: 1))
        for _ in 0..<500 {
            let choice = scheduler.next(after: start)
            let delay = choice.at.timeIntervalSince(start)
            #expect(delay >= 30 && delay <= 90)
        }
    }

    @Test func activityIsOneOfWaitingVideogameTennis() {
        var scheduler = IdleScheduler(rng: SeededGenerator(seed: 2))
        let allowed: Set<CompanionState> = [.waiting, .videogame, .tennis]
        for _ in 0..<500 {
            #expect(allowed.contains(scheduler.next(after: start).activity))
        }
    }

    @Test func everyActivityGetsPickedEventually() {
        var scheduler = IdleScheduler(rng: SeededGenerator(seed: 3))
        var seen: Set<CompanionState> = []
        for _ in 0..<200 { seen.insert(scheduler.next(after: start).activity) }
        #expect(seen == [.waiting, .videogame, .tennis])
    }

    @Test func sameSeedGivesSameSequence() {
        var a = IdleScheduler(rng: SeededGenerator(seed: 42))
        var b = IdleScheduler(rng: SeededGenerator(seed: 42))
        for _ in 0..<20 {
            #expect(a.next(after: start) == b.next(after: start))
        }
    }

    @Test func scheduledTimeIsRelativeToNow() {
        var a = IdleScheduler(rng: SeededGenerator(seed: 7))
        var b = IdleScheduler(rng: SeededGenerator(seed: 7))
        let later = start.addingTimeInterval(1_000)
        let first = a.next(after: start)
        let second = b.next(after: later)
        #expect(second.at.timeIntervalSince(later) == first.at.timeIntervalSince(start))
    }
}
