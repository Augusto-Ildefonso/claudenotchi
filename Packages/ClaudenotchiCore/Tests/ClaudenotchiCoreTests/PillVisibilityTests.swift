import Testing
@testable import ClaudenotchiCore

@Suite struct PillVisibilityTests {
    @Test func isVisibleWhileASessionIsOpen() {
        #expect(PillVisibility.isVisible(hideWhenClosed: true, sessionsOpen: true, state: .waiting))
        #expect(PillVisibility.isVisible(hideWhenClosed: true, sessionsOpen: true, state: .coding))
    }

    @Test func isHiddenWhenNoSessionIsOpen() {
        #expect(!PillVisibility.isVisible(hideWhenClosed: true, sessionsOpen: false, state: .waiting))
        #expect(!PillVisibility.isVisible(hideWhenClosed: true, sessionsOpen: false, state: .sleeping))
    }

    @Test func theCelebrationOfAFinishedSessionStillShows() {
        #expect(PillVisibility.isVisible(hideWhenClosed: true, sessionsOpen: false, state: .done))
    }

    @Test func aRequestForTheUserKeepsItVisible() {
        #expect(PillVisibility.isVisible(hideWhenClosed: true, sessionsOpen: false, state: .needsInput))
    }

    @Test func withTheOptionOffItIsAlwaysVisible() {
        #expect(PillVisibility.isVisible(hideWhenClosed: false, sessionsOpen: false, state: .waiting))
    }
}
