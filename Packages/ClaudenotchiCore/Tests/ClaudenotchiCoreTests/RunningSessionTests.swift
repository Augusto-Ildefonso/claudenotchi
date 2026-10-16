import Foundation
import Testing
@testable import ClaudenotchiCore

@Suite struct AdoptedSessionTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func event(_ type: SessionEvent.EventType, session: String = "real", at time: Date) -> SessionEvent {
        SessionEvent(sessionID: session, type: type, timestamp: time)
    }

    @Test func aClaudeThatWasAlreadyRunningCountsAsAnInteractiveSession() {
        var registry = SessionRegistry()
        registry.noteRunning(pid: 100, interactive: true, now: t0)
        #expect(registry.count == 1)
        #expect(registry.hasInteractiveSession)
    }

    @Test func notingTheSameProcessTwiceDoesNotDuplicateIt() {
        var registry = SessionRegistry()
        registry.noteRunning(pid: 100, interactive: true, now: t0)
        registry.noteRunning(pid: 100, interactive: true, now: t0 + 5)
        #expect(registry.count == 1)
    }

    @Test func theFirstRealEventOfThatProcessReplacesTheStandIn() {
        var registry = SessionRegistry()
        registry.noteRunning(pid: 100, interactive: true, now: t0)
        registry.handle(event(.userPromptSubmit, at: t0 + 1), claudePID: 100, interactive: true)
        #expect(registry.count == 1, "one session, not the stand-in plus the real one")
        registry.handle(event(.sessionEnd, at: t0 + 2), claudePID: 100, interactive: true)
        #expect(registry.isEmpty)
    }

    @Test func aProcessThatAlreadyHasARealSessionIsNotNotedAgain() {
        var registry = SessionRegistry()
        registry.handle(event(.sessionStart, at: t0), claudePID: 100, interactive: true)
        registry.noteRunning(pid: 100, interactive: true, now: t0 + 5)
        #expect(registry.count == 1)
    }

    @Test func theStandInGoesWhenItsProcessDies() {
        var registry = SessionRegistry()
        registry.noteRunning(pid: 100, interactive: true, now: t0)
        registry.prune(now: t0 + 1) { _ in false }
        #expect(registry.isEmpty)
    }

    @Test func theStandInOfAnotherProcessIsUntouchedByARealEvent() {
        var registry = SessionRegistry()
        registry.noteRunning(pid: 100, interactive: true, now: t0)
        registry.handle(event(.sessionStart, session: "other", at: t0 + 1), claudePID: 200, interactive: true)
        #expect(registry.count == 2)
    }

    @Test func aStandInThatIsNotInteractiveDoesNotShowThePill() {
        var registry = SessionRegistry()
        registry.noteRunning(pid: 100, interactive: false, now: t0)
        #expect(registry.count == 1)
        #expect(!registry.hasInteractiveSession)
    }
}

@Suite struct ProcessScannerTests {
    /// A little process table: pid -> (parent, command line, name).
    private struct Table {
        var parents: [Int: Int] = [:]
        var args: [Int: [String]] = [:]
        var tty: [Int: String] = [:]
        var apps: Set<Int> = []
        var names: [Int: String] = [:]

        func find() -> [RunningClaude] {
            ProcessScanner.findTerminalSessions(
                pids: Array(parents.keys).sorted(),
                parent: { parents[$0] },
                arguments: { args[$0] },
                isRegularApp: { apps.contains($0) },
                name: { names[$0] },
                tty: { tty[$0] }
            )
        }
    }

    private func ghosttyWithClaude() -> Table {
        var t = Table()
        t.parents = [900: 1, 901: 900, 902: 901, 903: 902]       // ghostty > login > zsh > claude
        t.args = [900: ["ghostty"], 901: ["login"], 902: ["-zsh"], 903: ["claude"]]
        t.apps = [900]
        t.tty = [903: "ttys004"]
        return t
    }

    @Test func findsAClaudeRunningInATerminal() {
        let found = ghosttyWithClaude().find()
        #expect(found.map(\.pid) == [903])
        #expect(found.first?.chain == [903, 902, 901, 900], "the chain up to the terminal app, for click-to-focus")
        #expect(found.first?.tty == "ttys004")
    }

    @Test func ignoresABackgroundClaudeWithNoTerminalAboveIt() {
        var t = Table()
        t.parents = [50: 1, 51: 50, 52: 51]                       // daemon > bg-pty-host > bg-spare
        t.args = [50: ["claude", "daemon", "run"], 51: ["claude", "bg-pty-host"], 52: ["claude", "bg-spare"]]
        #expect(t.find().isEmpty)
    }

    @Test func ignoresChildrenOfAClaudeThatAreClaudeToo() {
        var t = ghosttyWithClaude()
        t.parents[904] = 903                                       // e.g. a helper the session spawned
        t.args[904] = ["claude", "mcp", "serve"]
        #expect(t.find().map(\.pid) == [903])
    }

    @Test func ignoresOtherProcesses() {
        var t = ghosttyWithClaude()
        t.parents[905] = 902
        t.args[905] = ["vim", "claude.md"]
        #expect(t.find().map(\.pid) == [903])
    }

    @Test func findsSeveralSessionsInSeveralTerminals() {
        var t = ghosttyWithClaude()
        t.parents[910] = 1; t.parents[911] = 910; t.parents[912] = 911   // another window
        t.args[910] = ["iTerm2"]; t.args[911] = ["-zsh"]; t.args[912] = ["claude", "--resume"]
        t.apps.insert(910)
        #expect(t.find().map(\.pid) == [903, 912])
    }

    @Test func aClaudeInsideTmuxCounts() {
        var t = Table()
        t.parents = [70: 1, 71: 70, 72: 71]                        // tmux server > zsh > claude
        t.args = [70: ["tmux"], 71: ["-zsh"], 72: ["claude"]]
        t.names = [70: "tmux"]
        #expect(t.find().map(\.pid) == [72])
    }

    @Test func listsTheRealProcessesOfThisMachine() {
        let pids = ProcessScanner.allPIDs()
        #expect(pids.count > 10)
        #expect(pids.contains(Int(getpid())))
    }

    @Test func readsTheWorkingFolderOfAProcess() {
        let folder = ProcessAncestry.currentDirectory(of: getpid())
        #expect(folder != nil)
        #expect(folder.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
                == URL(fileURLWithPath: FileManager.default.currentDirectoryPath).resolvingSymlinksInPath().path)
    }

    @Test func aMissingProcessHasNoWorkingFolder() {
        #expect(ProcessAncestry.currentDirectory(of: 999_999) == nil)
    }
}

