import Foundation
import Testing
@testable import ClaudenotchiCore

@Suite struct SessionRegistryTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func event(_ type: SessionEvent.EventType, session: String = "a", at time: Date) -> SessionEvent {
        SessionEvent(sessionID: session, type: type, timestamp: time)
    }

    @Test func startsEmpty() {
        let registry = SessionRegistry()
        #expect(registry.isEmpty)
        #expect(registry.count == 0)
    }

    @Test func aSessionStartAddsASession() {
        var registry = SessionRegistry()
        registry.handle(event(.sessionStart, at: t0), claudePID: 100)
        #expect(!registry.isEmpty)
        #expect(registry.count == 1)
    }

    @Test func anyEventRegistersASessionTheAppMissedTheStartOf() {
        var registry = SessionRegistry()
        registry.handle(event(.preToolUse, at: t0), claudePID: 100)
        #expect(registry.count == 1)
    }

    @Test func eventsOfOneSessionCountOnce() {
        var registry = SessionRegistry()
        registry.handle(event(.sessionStart, at: t0), claudePID: 100)
        registry.handle(event(.userPromptSubmit, at: t0 + 1), claudePID: 100)
        #expect(registry.count == 1)
    }

    @Test func separateSessionsAreCountedSeparately() {
        var registry = SessionRegistry()
        registry.handle(event(.sessionStart, session: "a", at: t0), claudePID: 100)
        registry.handle(event(.sessionStart, session: "b", at: t0), claudePID: 200)
        #expect(registry.count == 2)
    }

    @Test func sessionEndRemovesOnlyThatSession() {
        var registry = SessionRegistry()
        registry.handle(event(.sessionStart, session: "a", at: t0), claudePID: 100)
        registry.handle(event(.sessionStart, session: "b", at: t0), claudePID: 200)
        registry.handle(event(.sessionEnd, session: "a", at: t0 + 5), claudePID: 100)
        #expect(registry.count == 1)
        registry.handle(event(.sessionEnd, session: "b", at: t0 + 6), claudePID: 200)
        #expect(registry.isEmpty)
    }

    @Test func aSessionEndForAnUnknownSessionChangesNothing() {
        var registry = SessionRegistry()
        registry.handle(event(.sessionEnd, session: "ghost", at: t0), claudePID: nil)
        #expect(registry.isEmpty)
    }

    // MARK: sessions that vanish without a SessionEnd (terminal closed, crash, kill -9)

    @Test func pruneDropsASessionWhoseProcessIsGone() {
        var registry = SessionRegistry()
        registry.handle(event(.sessionStart, at: t0), claudePID: 100)
        registry.prune(now: t0 + 1) { _ in false }
        #expect(registry.isEmpty)
    }

    @Test func pruneKeepsASessionWhoseProcessIsAlive() {
        var registry = SessionRegistry()
        registry.handle(event(.sessionStart, at: t0), claudePID: 100)
        registry.prune(now: t0 + 86_400) { $0 == 100 } // a quiet session that is still open stays
        #expect(registry.count == 1)
    }

    @Test func pruneChecksEachSessionsOwnProcess() {
        var registry = SessionRegistry()
        registry.handle(event(.sessionStart, session: "a", at: t0), claudePID: 100)
        registry.handle(event(.sessionStart, session: "b", at: t0), claudePID: 200)
        registry.prune(now: t0 + 1) { $0 == 200 }
        #expect(registry.count == 1)
    }

    @Test func aLaterEventUpdatesTheProcessOfASession() {
        var registry = SessionRegistry()
        registry.handle(event(.sessionStart, at: t0), claudePID: 100)
        registry.handle(event(.userPromptSubmit, at: t0 + 1), claudePID: 300) // `claude --resume` in a new process
        registry.prune(now: t0 + 2) { $0 == 300 }
        #expect(registry.count == 1)
    }

    @Test func anEventWithoutAProcessKeepsTheKnownOne() {
        var registry = SessionRegistry()
        registry.handle(event(.sessionStart, at: t0), claudePID: 100)
        registry.handle(event(.postToolUse, at: t0 + 1), claudePID: nil)
        registry.prune(now: t0 + 2) { _ in false }
        #expect(registry.isEmpty, "the remembered pid 100 is checked and found dead")
    }

    @Test func aSessionWithNoKnownProcessExpiresAfterALongSilence() {
        var registry = SessionRegistry()
        registry.handle(event(.sessionStart, at: t0), claudePID: nil)
        registry.prune(now: t0 + SessionRegistry.silenceLimit - 1) { _ in true }
        #expect(registry.count == 1)
        registry.prune(now: t0 + SessionRegistry.silenceLimit + 1) { _ in true }
        #expect(registry.isEmpty)
    }

    @Test func silenceRestartsWithEachEvent() {
        var registry = SessionRegistry()
        registry.handle(event(.sessionStart, at: t0), claudePID: nil)
        registry.handle(event(.postToolUse, at: t0 + SessionRegistry.silenceLimit - 10), claudePID: nil)
        registry.prune(now: t0 + SessionRegistry.silenceLimit + 1) { _ in true }
        #expect(registry.count == 1)
    }
}

@Suite struct ClaudeProcessLookupTests {
    // Real Claude Code reports its version number as the process name (the binary is `versions/2.1.300`),
    // so it is recognised by its command line instead.
    @Test func recognisesTheNativeInstall() {
        #expect(ProcessAncestry.looksLikeClaude(arguments: ["claude"]))
        #expect(ProcessAncestry.looksLikeClaude(arguments: ["claude", "-p", "hello"]))
        #expect(ProcessAncestry.looksLikeClaude(arguments: ["/Users/me/.local/bin/claude", "--resume"]))
    }

    @Test func recognisesAnNpmInstallRunningUnderNode() {
        #expect(ProcessAncestry.looksLikeClaude(arguments: ["node", "/opt/homebrew/bin/claude"]))
        #expect(ProcessAncestry.looksLikeClaude(arguments: ["/usr/local/bin/node", "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"]))
    }

    @Test func ignoresShellsAndOtherPrograms() {
        #expect(!ProcessAncestry.looksLikeClaude(arguments: ["/bin/zsh", "-c", "claude -p hi"]))
        #expect(!ProcessAncestry.looksLikeClaude(arguments: ["sh", "-c", "/path/claude-hook"]))
        #expect(!ProcessAncestry.looksLikeClaude(arguments: ["node", "server.js"]))
        #expect(!ProcessAncestry.looksLikeClaude(arguments: ["vim", "claude"]))
        #expect(!ProcessAncestry.looksLikeClaude(arguments: []))
    }

    @Test func picksTheNearestAncestorThatIsClaude() {
        let args: [Int: [String]] = [10: ["sh", "-c", "x"], 11: ["claude"], 12: ["zsh"], 13: ["claude", "bg-pty-host"]]
        #expect(ProcessAncestry.claudePID(in: [10, 11, 12, 13], arguments: { args[$0] }) == 11)
    }

    @Test func isNilWhenNoAncestorIsClaude() {
        let args: [Int: [String]] = [10: ["sh"], 12: ["zsh"]]
        #expect(ProcessAncestry.claudePID(in: [10, 12], arguments: { args[$0] }) == nil)
        #expect(ProcessAncestry.claudePID(in: [], arguments: { _ in ["claude"] }) == nil)
    }

    @Test func readsTheArgumentsOfARunningProcess() {
        let args = ProcessAncestry.arguments(of: getpid())
        #expect(args != nil && !(args ?? []).isEmpty)
        #expect(args?.first?.isEmpty == false)
    }

    @Test func aMissingProcessHasNoArguments() {
        #expect(ProcessAncestry.arguments(of: 999_999) == nil)
    }

    @Test func aFinishedButUnreapedProcessIsNotRunning() throws {
        var pid: pid_t = 0
        let status = posix_spawn(&pid, "/usr/bin/true", nil, nil, ["true", nil].map { $0.flatMap { strdup($0) } }, nil)
        try #require(status == 0)
        defer { var s: Int32 = 0; waitpid(pid, &s, 0) }
        #expect(ProcessAncestry.isRunning(Int(getpid())))
        // /usr/bin/true exits at once and stays a zombie until waitpid, which the defer above does later.
        var waited = 0
        while ProcessAncestry.isRunning(Int(pid)), waited < 100 { usleep(20_000); waited += 1 }
        #expect(!ProcessAncestry.isRunning(Int(pid)))
    }
}
