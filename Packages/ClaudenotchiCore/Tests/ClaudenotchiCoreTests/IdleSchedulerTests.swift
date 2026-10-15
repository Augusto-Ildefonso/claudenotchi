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

    // MARK: configurable activities (from the sprite manifest)

    @Test func picksOnlyFromTheActivitiesItWasGiven() {
        var scheduler = IdleScheduler(activities: [.tennis, .videogame], rng: SeededGenerator(seed: 5))
        var seen: Set<CompanionState> = []
        for _ in 0..<200 { seen.insert(scheduler.next(after: start).activity) }
        #expect(seen == [.tennis, .videogame])
    }

    @Test func aSingleActivityIsAlwaysChosen() {
        var scheduler = IdleScheduler(activities: [.videogame], rng: SeededGenerator(seed: 6))
        for _ in 0..<50 { #expect(scheduler.next(after: start).activity == .videogame) }
    }

    @Test func anEmptyListFallsBackToWaiting() {
        var scheduler = IdleScheduler(activities: [], rng: SeededGenerator(seed: 7))
        for _ in 0..<20 { #expect(scheduler.next(after: start).activity == .waiting) }
    }

    @Test func theDefaultActivitiesAreWaitingVideogameTennis() {
        #expect(IdleScheduler.defaultActivities == [.waiting, .videogame, .tennis])
    }

    @Test func manifestNamesBecomeActivities() {
        #expect(IdleScheduler.activities(fromManifestNames: ["waiting", "tennis"]) == [.waiting, .tennis])
    }

    @Test func unknownNamesAreIgnored() {
        #expect(IdleScheduler.activities(fromManifestNames: ["waiting", "moonwalk", "tennis"]) == [.waiting, .tennis])
    }

    @Test func statesThatAreNotIdleActivitiesAreIgnored() {
        // The state machine only rotates among idle states; a busy state in the list would never end.
        #expect(IdleScheduler.activities(fromManifestNames: ["coding", "videogame", "needsInput", "sleeping"]) == [.videogame])
    }

    @Test func duplicatesAreCollapsedKeepingTheFirstPosition() {
        #expect(IdleScheduler.activities(fromManifestNames: ["tennis", "waiting", "tennis"]) == [.tennis, .waiting])
    }

    @Test func anUnusableManifestListGivesTheDefaults() {
        #expect(IdleScheduler.activities(fromManifestNames: []) == IdleScheduler.defaultActivities)
        #expect(IdleScheduler.activities(fromManifestNames: ["nonsense", "coding"]) == IdleScheduler.defaultActivities)
    }

    @Test func idleStatesAreExactlyTheOnesTheMachineRotatesThrough() {
        #expect(Set(CompanionState.allCases.filter(\.isIdleActivity)) == [.waiting, .videogame, .tennis])
    }
}
