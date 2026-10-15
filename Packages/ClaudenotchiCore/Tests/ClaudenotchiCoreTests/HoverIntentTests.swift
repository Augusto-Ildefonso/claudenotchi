import Foundation
import Testing
@testable import ClaudenotchiCore

@Suite struct HoverIntentTests {
    let t0 = Date(timeIntervalSince1970: 50_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    @Test func startsCollapsed() {
        #expect(HoverIntent(expandDelay: 0.5).isExpanded == false)
    }

    @Test func expandsOnlyAfterTheChosenDelay() {
        var hover = HoverIntent(expandDelay: 0.5)
        hover.mouseEntered(at: t0)
        hover.tick(now: at(0.49))
        #expect(hover.isExpanded == false)
        hover.tick(now: at(0.5))
        #expect(hover.isExpanded == true)
    }

    @Test func zeroDelayExpandsImmediately() {
        var hover = HoverIntent(expandDelay: 0)
        hover.mouseEntered(at: t0)
        hover.tick(now: t0)
        #expect(hover.isExpanded)
    }

    @Test func leavingBeforeTheDelayCancelsTheExpansion() {
        var hover = HoverIntent(expandDelay: 1)
        hover.mouseEntered(at: t0)
        hover.mouseExited(at: at(0.4))
        hover.tick(now: at(2))
        #expect(hover.isExpanded == false)
    }

    @Test func enteringAgainRestartsTheWait() {
        var hover = HoverIntent(expandDelay: 1)
        hover.mouseEntered(at: t0)
        hover.mouseExited(at: at(0.6))
        hover.mouseEntered(at: at(0.8))
        hover.tick(now: at(1.4)) // 1.4s after the first enter, but only 0.6s after the second
        #expect(hover.isExpanded == false)
        hover.tick(now: at(1.8))
        #expect(hover.isExpanded)
    }

    @Test func enteringWhileAlreadyInsideDoesNotRestartTheWait() {
        var hover = HoverIntent(expandDelay: 1)
        hover.mouseEntered(at: t0)
        hover.mouseEntered(at: at(0.9))
        hover.tick(now: at(1))
        #expect(hover.isExpanded)
    }

    @Test func staysExpandedWhileTheMouseIsInside() {
        var hover = HoverIntent(expandDelay: 0.2)
        hover.mouseEntered(at: t0)
        hover.tick(now: at(0.2))
        hover.tick(now: at(60))
        #expect(hover.isExpanded)
    }

    @Test func collapsesAfterAShortGraceOnceTheMouseLeaves() {
        var hover = HoverIntent(expandDelay: 0.2, collapseGrace: 0.25)
        hover.mouseEntered(at: t0)
        hover.tick(now: at(0.2))
        hover.mouseExited(at: at(5))
        hover.tick(now: at(5.24))
        #expect(hover.isExpanded)
        hover.tick(now: at(5.25))
        #expect(hover.isExpanded == false)
    }

    @Test func comingBackWithinTheGraceKeepsItExpanded() {
        var hover = HoverIntent(expandDelay: 0.2, collapseGrace: 0.25)
        hover.mouseEntered(at: t0)
        hover.tick(now: at(0.2))
        hover.mouseExited(at: at(5))
        hover.mouseEntered(at: at(5.1))
        hover.tick(now: at(10))
        #expect(hover.isExpanded)
    }

    @Test func negativeDelayMeansNeverExpand() {
        var hover = HoverIntent(expandDelay: -1)
        hover.mouseEntered(at: t0)
        hover.tick(now: at(1_000))
        #expect(hover.isExpanded == false)
    }

    @Test func changingTheDelayAppliesToTheCurrentHover() {
        var hover = HoverIntent(expandDelay: 3)
        hover.mouseEntered(at: t0)
        hover.tick(now: at(1))
        #expect(hover.isExpanded == false)
        hover.expandDelay = 0.5
        hover.tick(now: at(1))
        #expect(hover.isExpanded)
    }

    @Test func turningHoverOffCollapsesAnExpandedPill() {
        var hover = HoverIntent(expandDelay: 0.2, collapseGrace: 0.25)
        hover.mouseEntered(at: t0)
        hover.tick(now: at(0.2))
        hover.expandDelay = -1
        hover.tick(now: at(0.3))
        #expect(hover.isExpanded == false)
    }

    @Test func needsTicksOnlyWhileInsideOrExpanded() {
        var hover = HoverIntent(expandDelay: 0.2, collapseGrace: 0.25)
        #expect(hover.needsTicks == false)
        hover.mouseEntered(at: t0)
        #expect(hover.needsTicks)
        hover.tick(now: at(0.2))
        hover.mouseExited(at: at(1))
        #expect(hover.needsTicks) // still expanded, grace running
        hover.tick(now: at(1.25))
        #expect(hover.needsTicks == false)
    }
}

@Suite struct StatusTextTests {
    @Test func everyStateHasAHumanReadableTitle() {
        for state in CompanionState.allCases {
            #expect(!state.title.isEmpty, "\(state)")
        }
    }

    @Test func titlesDescribeWhatClaudeIsDoing() {
        #expect(CompanionState.thinking.title == "Thinking…")
        #expect(CompanionState.coding.title == "Editing files")
        #expect(CompanionState.reading.title == "Reading")
        #expect(CompanionState.bash.title == "Running a command")
        #expect(CompanionState.web.title == "Searching the web")
        #expect(CompanionState.needsInput.title == "Needs your input")
        #expect(CompanionState.done.title == "Done")
    }
}
