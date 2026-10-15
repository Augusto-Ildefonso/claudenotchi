import Darwin
import Foundation
import Testing
@testable import ClaudenotchiCore

@Suite struct ProcessAncestryTests {
    @Test func theParentOfThisProcessIsOurParent() {
        #expect(ProcessAncestry.parent(of: getpid()) == getppid())
    }

    @Test func aProcessThatDoesNotExistHasNoParent() {
        #expect(ProcessAncestry.parent(of: 2_000_000) == nil)
    }

    @Test func ancestorsStartAtTheGivenProcessAndFollowParents() {
        let chain = ProcessAncestry.ancestors(startingAt: getpid())
        #expect(chain.first == Int(getpid()))
        for (child, parent) in zip(chain, chain.dropFirst()) {
            #expect(ProcessAncestry.parent(of: Int32(child)) == Int32(parent))
        }
    }

    @Test func theChainHasNoRepeatsAndStopsBeforeLaunchd() {
        let chain = ProcessAncestry.ancestors(startingAt: getpid())
        #expect(Set(chain).count == chain.count)
        #expect(!chain.contains(0))
        #expect(!chain.contains(1))
    }

    @Test func theChainIsCappedAtTheLimit() {
        #expect(ProcessAncestry.ancestors(startingAt: getpid(), limit: 1) == [Int(getpid())])
    }

    @Test func aMissingProcessGivesAnEmptyChain() {
        #expect(ProcessAncestry.ancestors(startingAt: 2_000_000).isEmpty)
    }

    @Test func currentStartsAtTheParentProcess() {
        let info = ProcessAncestry.current()
        #expect(info.pids.first == Int(getppid()))
    }

    @Test func aTerminalNameLooksLikeAttyDeviceWhenThereIsOne() {
        // Under a test runner there may be no controlling terminal; if there is one it is "ttysNNN".
        if let name = ProcessAncestry.controllingTTY(of: getpid()) {
            #expect(name.hasPrefix("tty"))
        }
    }

    @Test func theTerminalOfAMissingProcessIsUnknown() {
        #expect(ProcessAncestry.controllingTTY(of: 2_000_000) == nil)
    }
}
