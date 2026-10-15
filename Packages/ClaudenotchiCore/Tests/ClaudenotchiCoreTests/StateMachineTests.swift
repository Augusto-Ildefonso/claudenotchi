import Foundation
import Testing
@testable import ClaudenotchiCore

@Suite struct StateMachineTests {
    let t0 = Date(timeIntervalSince1970: 100_000)

    private func machine(idle: [(CompanionState, TimeInterval)] = []) -> StateMachine {
        StateMachine(now: t0, scheduler: ScriptedIdle(idle))
    }

    // MARK: event -> state

    @Test func startsWaiting() {
        #expect(machine().state == .waiting)
    }

    @Test func userPromptSubmitStartsThinking() {
        var m = machine()
        m.handle(event(.userPromptSubmit, at: t0))
        #expect(m.state == .thinking)
    }

    @Test(arguments: [
        ("Edit", CompanionState.coding), ("Write", .coding), ("MultiEdit", .coding), ("NotebookEdit", .coding),
        ("Read", .reading), ("Grep", .reading), ("Glob", .reading),
        ("Bash", .bash),
        ("WebSearch", .web), ("WebFetch", .web),
        ("Task", .thinking), ("TodoWrite", .thinking), ("mcp__github__list_prs", .thinking),
    ])
    func preToolUseMapsToolToState(tool: String, expected: CompanionState) {
        var m = machine()
        m.handle(event(.userPromptSubmit, at: t0))
        m.handle(event(.preToolUse, tool: tool, at: t0.addingTimeInterval(1)))
        #expect(m.state == expected)
    }

    @Test func preToolUseWithoutToolNameIsThinking() {
        var m = machine()
        m.handle(event(.preToolUse, tool: nil, at: t0))
        #expect(m.state == .thinking)
    }

    @Test func postToolUseGoesBackToThinking() {
        var m = machine()
        m.handle(event(.preToolUse, tool: "Edit", at: t0))
        m.handle(event(.postToolUse, tool: "Edit", at: t0.addingTimeInterval(1)))
        #expect(m.state == .thinking)
    }

    @Test(arguments: [SessionEvent.EventType.notification, .permissionRequest])
    func attentionEventsNeedInput(type: SessionEvent.EventType) {
        var m = machine()
        m.handle(event(.preToolUse, tool: "Bash", at: t0))
        m.handle(event(type, at: t0.addingTimeInterval(1)))
        #expect(m.state == .needsInput)
    }

    // MARK: needsInput priority

    // Real Claude Code: after a denied permission prompt there is no PostToolUse; the next event is a
    // PreToolUse for the next tool. So a new tool starting means the prompt was resolved.
    @Test func aNewToolStartingMeansThePermissionPromptWasResolved() {
        var m = machine()
        m.handle(event(.permissionRequest, tool: "Bash", at: t0))
        m.handle(event(.preToolUse, tool: "Edit", at: t0.addingTimeInterval(1)))
        #expect(m.state == .coding)
    }

    @Test func needsInputEndsWhenToolFinishes() {
        var m = machine()
        m.handle(event(.permissionRequest, at: t0))
        m.handle(event(.postToolUse, tool: "Bash", at: t0.addingTimeInterval(5)))
        #expect(m.state == .thinking)
    }

    @Test func needsInputEndsOnStop() {
        var m = machine()
        m.handle(event(.permissionRequest, at: t0))
        m.handle(event(.stop, at: t0.addingTimeInterval(5)))
        #expect(m.state == .done)
    }

    @Test func needsInputEndsWhenUserSubmitsNewPrompt() {
        var m = machine()
        m.handle(event(.notification, at: t0))
        m.handle(event(.userPromptSubmit, at: t0.addingTimeInterval(5)))
        #expect(m.state == .thinking)
    }

    @Test func needsInputNeverTimesOut() {
        var m = machine()
        m.handle(event(.permissionRequest, at: t0))
        m.tick(now: t0.addingTimeInterval(10_000))
        #expect(m.state == .needsInput)
    }

    @Test func answeringThePromptInTheNotchGoesBackToThinking() {
        var m = machine()
        m.handle(event(.permissionRequest, at: t0))
        m.promptAnswered(at: t0.addingTimeInterval(3))
        #expect(m.state == .thinking)
        #expect(m.stateSince == t0.addingTimeInterval(3))
    }

    @Test func answeringWhenNothingIsWaitingChangesNothing() {
        var m = machine()
        m.handle(event(.preToolUse, tool: "Edit", at: t0))
        m.promptAnswered(at: t0.addingTimeInterval(1))
        #expect(m.state == .coding)
    }

    // Pressing Esc on a dialog sends no hook event at all; the only sign is the waiting hook being killed.
    @Test func aCancelledPromptLeavesNeedsInput() {
        var m = machine()
        m.handle(event(.permissionRequest, at: t0))
        m.promptCancelled(at: t0.addingTimeInterval(4))
        #expect(m.state == .waiting)
        #expect(m.stateSince == t0.addingTimeInterval(4))
    }

    @Test func cancellingWhenNothingIsWaitingChangesNothing() {
        var m = machine()
        m.handle(event(.preToolUse, tool: "Edit", at: t0))
        m.promptCancelled(at: t0.addingTimeInterval(1))
        #expect(m.state == .coding)
    }

    @Test func aCancelledPromptCountsAsActivityForSleep() {
        var m = machine(idle: [(.waiting, 1_000)])
        m.handle(event(.permissionRequest, at: t0))
        m.promptCancelled(at: t0.addingTimeInterval(250))
        m.tick(now: t0.addingTimeInterval(540))
        #expect(m.state == .waiting, "290s after the cancel is still within the 5 minutes")
    }

    // MARK: error

    @Test func toolFailureShowsError() {
        var m = machine()
        m.handle(event(.preToolUse, tool: "Bash", at: t0))
        m.handle(event(.postToolUseFailure, tool: "Bash", at: t0.addingTimeInterval(1)))
        #expect(m.state == .error)
    }

    @Test func aToolInterruptedByTheUserIsNotAnError() {
        var m = machine()
        m.handle(event(.preToolUse, tool: "Bash", at: t0))
        m.handle(SessionEvent(sessionID: "s1", type: .postToolUseFailure, tool: "Bash", timestamp: t0.addingTimeInterval(1), isInterrupt: true))
        #expect(m.state == .thinking)
    }

    @Test func errorHoldsForThreeSecondsThenThinking() {
        var m = machine()
        m.handle(event(.postToolUseFailure, at: t0))
        m.tick(now: t0.addingTimeInterval(2.9))
        #expect(m.state == .error)
        m.tick(now: t0.addingTimeInterval(3))
        #expect(m.state == .thinking)
    }

    @Test func errorIsNotInterruptedByNextToolWithinThreeSeconds() {
        var m = machine()
        m.handle(event(.postToolUseFailure, at: t0))
        m.handle(event(.preToolUse, tool: "Edit", at: t0.addingTimeInterval(1)))
        #expect(m.state == .error)
        m.handle(event(.preToolUse, tool: "Edit", at: t0.addingTimeInterval(4)))
        #expect(m.state == .coding)
    }

    @Test func newPromptInterruptsError() {
        var m = machine()
        m.handle(event(.postToolUseFailure, at: t0))
        m.handle(event(.userPromptSubmit, at: t0.addingTimeInterval(1)))
        #expect(m.state == .thinking)
    }

    // MARK: done

    @Test func stopShowsDoneThenWaitingAfterFiveSeconds() {
        var m = machine()
        m.handle(event(.userPromptSubmit, at: t0))
        m.handle(event(.stop, at: t0.addingTimeInterval(10)))
        #expect(m.state == .done)
        m.tick(now: t0.addingTimeInterval(14.9))
        #expect(m.state == .done)
        m.tick(now: t0.addingTimeInterval(15))
        #expect(m.state == .waiting)
    }

    @Test func newPromptInterruptsDone() {
        var m = machine()
        m.handle(event(.stop, at: t0))
        m.handle(event(.userPromptSubmit, at: t0.addingTimeInterval(2)))
        #expect(m.state == .thinking)
    }

    // MARK: idle rotation and sleep

    @Test func idleActivityChangesWhenScheduledTimeArrives() {
        var m = machine(idle: [(.tennis, 40), (.waiting, 20)])
        m.tick(now: t0.addingTimeInterval(39))
        #expect(m.state == .waiting)
        m.tick(now: t0.addingTimeInterval(40))
        #expect(m.state == .tennis)
        m.tick(now: t0.addingTimeInterval(59))
        #expect(m.state == .tennis)
        m.tick(now: t0.addingTimeInterval(60))
        #expect(m.state == .waiting)
    }

    @Test func fallingBackToWaitingAfterDoneSchedulesIdleFromThen() {
        var m = machine(idle: [(.videogame, 30)])
        m.handle(event(.stop, at: t0))
        m.tick(now: t0.addingTimeInterval(5))
        #expect(m.state == .waiting)
        m.tick(now: t0.addingTimeInterval(34))
        #expect(m.state == .waiting)
        m.tick(now: t0.addingTimeInterval(35))
        #expect(m.state == .videogame)
    }

    @Test func sleepsAfterFiveMinutesWithoutEvents() {
        var m = machine(idle: [(.tennis, 1_000)])
        m.tick(now: t0.addingTimeInterval(299))
        #expect(m.state == .waiting)
        m.tick(now: t0.addingTimeInterval(300))
        #expect(m.state == .sleeping)
    }

    @Test func sleepWinsWhenIdleChangeIsAlsoDue() {
        var m = machine(idle: [(.tennis, 30)])
        m.tick(now: t0.addingTimeInterval(400))
        #expect(m.state == .sleeping)
    }

    @Test func anyEventPostponesSleep() {
        var m = machine(idle: [(.waiting, 1_000)])
        m.handle(event(.unknown, at: t0.addingTimeInterval(200)))
        m.tick(now: t0.addingTimeInterval(450))
        #expect(m.state != .sleeping)
        m.tick(now: t0.addingTimeInterval(500))
        #expect(m.state == .sleeping)
    }

    @Test func busyStatesNeverSleep() {
        var m = machine()
        m.handle(event(.preToolUse, tool: "Bash", at: t0))
        m.tick(now: t0.addingTimeInterval(1_000))
        #expect(m.state == .bash)
    }

    @Test func unknownEventWakesFromSleep() {
        var m = machine(idle: [(.waiting, 1_000)])
        m.tick(now: t0.addingTimeInterval(300))
        #expect(m.state == .sleeping)
        m.handle(event(.unknown, at: t0.addingTimeInterval(310)))
        #expect(m.state == .waiting)
    }

    @Test func promptWakesFromSleep() {
        var m = machine(idle: [(.waiting, 1_000)])
        m.tick(now: t0.addingTimeInterval(300))
        m.handle(event(.userPromptSubmit, at: t0.addingTimeInterval(310)))
        #expect(m.state == .thinking)
    }

    @Test func sessionEndGoesBackToWaiting() {
        var m = machine()
        m.handle(event(.preToolUse, tool: "Edit", at: t0))
        m.handle(event(.sessionEnd, at: t0.addingTimeInterval(1)))
        #expect(m.state == .waiting)
    }

    // Real Claude Code sends SessionEnd right after Stop when a session finishes.
    @Test func sessionEndDoesNotCutShortTheDoneCelebration() {
        var m = machine()
        m.handle(event(.stop, at: t0))
        m.handle(event(.sessionEnd, at: t0.addingTimeInterval(0.02)))
        #expect(m.state == .done)
        m.tick(now: t0.addingTimeInterval(5))
        #expect(m.state == .waiting)
    }

    // MARK: sprite names

    @Test func spriteNamesMatchTheSpriteManifest() {
        #expect(CompanionState.needsInput.spriteName == "alert")
        #expect(CompanionState.done.spriteName == "celebrating")
        #expect(CompanionState.coding.spriteName == "coding")
        #expect(CompanionState.videogame.spriteName == "videogame")
    }
}
