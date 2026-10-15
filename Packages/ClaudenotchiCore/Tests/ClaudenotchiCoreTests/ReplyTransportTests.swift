import Darwin
import Foundation
import Testing
@testable import ClaudenotchiCore

private func tempSocketPath() -> String {
    "/tmp/cn-\(UUID().uuidString.prefix(8)).sock"
}

private let sampleTime = Date(timeIntervalSince1970: 5_000)

private func permissionEvent(tool: String = "Bash", message: String = "Bash: touch a.txt") -> SessionEvent {
    SessionEvent(sessionID: "s1", type: .permissionRequest, tool: tool, message: message,
                 timestamp: sampleTime, expectsReply: true)
}

private func plainEvent(_ type: SessionEvent.EventType) -> SessionEvent {
    SessionEvent(sessionID: "s1", type: type, timestamp: sampleTime)
}

/// Waits for the first event satisfying `predicate`, up to `timeout`.
private func firstEvent(
    from server: EventServer, timeout: Duration = .seconds(3), where predicate: @escaping @Sendable (SessionEvent) -> Bool = { _ in true }
) async -> SessionEvent? {
    await withTaskGroup(of: SessionEvent?.self) { group in
        group.addTask {
            for await event in server.events where predicate(event) { return event }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

/// Waits for the next cancelled request id.
private func firstCancellation(from server: EventServer, timeout: Duration = .seconds(3)) async -> String? {
    await withTaskGroup(of: String?.self) { group in
        group.addTask {
            for await id in server.cancellations { return id }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

/// Runs blocking work on a plain dispatch queue. The client blocks in a socket read, and blocking
/// threads of Swift's small cooperative pool would starve the very tasks that must answer it.
private func offPool<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async { continuation.resume(returning: work()) }
    }
}

private func blockingSend(_ event: SessionEvent, to path: String) -> Task<PermissionDecision?, Never> {
    Task { await offPool { try? EventClient.sendAndAwaitReply(event, to: path) } }
}

@Suite struct ReplyTransportTests {
    @Test func serverGivesPermissionRequestsAnIDAndAnswersOnTheSameConnection() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        let answer = blockingSend(permissionEvent(), to: path)
        let event = try #require(await firstEvent(from: server))
        let id = try #require(event.requestID)
        #expect(event.type == .permissionRequest)

        #expect(server.reply(to: id, with: .allow))
        #expect(await answer.value == .allow)
    }

    @Test func aDenyMessageReachesTheClient() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        let answer = blockingSend(permissionEvent(), to: path)
        let id = try #require(await firstEvent(from: server)?.requestID)
        server.reply(to: id, with: .deny(message: "Not now"))
        #expect(await answer.value == .deny(message: "Not now"))
    }

    @Test func otherEventsKeepFlowingWhileAPromptIsWaiting() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        let answer = blockingSend(permissionEvent(), to: path)
        let request = try #require(await firstEvent(from: server))
        let id = try #require(request.requestID)

        try EventClient.send(plainEvent(.postToolUse), to: path)
        let next = await firstEvent(from: server)
        #expect(next?.type == .postToolUse, "a pending prompt must not block the server")

        server.reply(to: id, with: .allow)
        #expect(await answer.value == .allow)
    }

    @Test func eachPromptGetsItsOwnID() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        let first = blockingSend(permissionEvent(message: "one"), to: path)
        let firstID = try #require(await firstEvent(from: server)?.requestID)
        let second = blockingSend(permissionEvent(message: "two"), to: path)
        let secondID = try #require(await firstEvent(from: server)?.requestID)
        #expect(firstID != secondID)

        server.reply(to: secondID, with: .deny(message: nil))
        server.reply(to: firstID, with: .allow)
        #expect(await second.value == .deny(message: nil))
        #expect(await first.value == .allow)
    }

    @Test func aPromptCanOnlyBeAnsweredOnce() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        let answer = blockingSend(permissionEvent(), to: path)
        let id = try #require(await firstEvent(from: server)?.requestID)
        #expect(server.reply(to: id, with: .allow))
        #expect(server.reply(to: id, with: .deny(message: nil)) == false)
        #expect(await answer.value == .allow)
    }

    @Test func replyingToAnUnknownRequestDoesNothing() throws {
        let server = EventServer(path: tempSocketPath())
        #expect(server.reply(to: "nope", with: .allow) == false)
    }

    @Test func cancellingClosesTheConnectionWithoutAnAnswer() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        let answer = blockingSend(permissionEvent(), to: path)
        let id = try #require(await firstEvent(from: server)?.requestID)
        server.cancel(requestID: id)
        #expect(await answer.value == nil)
        #expect(server.reply(to: id, with: .allow) == false)
    }

    @Test func aClientThatDisconnectsIsReportedAsCancelled() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        // A helper killed because the user answered in the terminal: connect, send, hang up.
        try EventClient.sendRaw(permissionEvent().wireLine(), to: path)
        let id = try #require(await firstEvent(from: server)?.requestID)
        #expect(await firstCancellation(from: server) == id)
        #expect(server.reply(to: id, with: .allow) == false)
    }

    @Test func stoppingTheServerReleasesWaitingClients() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()

        let answer = blockingSend(permissionEvent(), to: path)
        _ = try #require(await firstEvent(from: server)?.requestID)
        server.stop()
        #expect(await answer.value == nil)
    }

    @Test func eventsThatDoNotExpectAReplyAreNotKeptOpen() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        try EventClient.send(plainEvent(.stop), to: path)
        let event = await firstEvent(from: server)
        #expect(event?.requestID == nil)
        #expect(event?.expectsReply == false)
    }
}

@Suite struct HookRunnerReplyTests {
    private let permissionJSON = #"{"session_id":"abc","cwd":"/tmp/p","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"touch a.txt"}}"#

    private func handle(_ json: String, path: String, ancestry: @escaping @Sendable () -> (pids: [Int], tty: String?) = { ([], nil) }) -> Task<HookRunner.Outcome, Never> {
        Task { await offPool { HookRunner.handle(stdin: Data(json.utf8), socketPath: path, now: sampleTime, ancestry: ancestry) } }
    }

    @Test func printsTheDecisionTheUserChose() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        let outcome = handle(permissionJSON, path: path)
        let id = try #require(await firstEvent(from: server)?.requestID)
        server.reply(to: id, with: .allow)

        let result = await outcome.value
        #expect(result.delivered)
        #expect(result.output == PermissionDecision.allow.hookOutput)
    }

    @Test func printsADenyWithItsMessage() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        let outcome = handle(permissionJSON, path: path)
        let id = try #require(await firstEvent(from: server)?.requestID)
        server.reply(to: id, with: .deny(message: "Denied from Claudenotchi"))
        #expect(await outcome.value.output == PermissionDecision.deny(message: "Denied from Claudenotchi").hookOutput)
    }

    @Test func printsNothingWhenTheAppClosesWithoutAnAnswer() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        let outcome = handle(permissionJSON, path: path)
        let id = try #require(await firstEvent(from: server)?.requestID)
        server.cancel(requestID: id)

        let result = await outcome.value
        #expect(result.delivered)
        #expect(result.output == nil, "no output lets Claude Code show its normal prompt")
    }

    @Test func printsNothingWhenTheAppIsNotRunning() async {
        let result = await handle(permissionJSON, path: tempSocketPath()).value
        #expect(result == HookRunner.Outcome(delivered: false, output: nil))
    }

    @Test func otherEventsDoNotWaitForAnAnswer() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        let result = await handle(#"{"session_id":"abc","hook_event_name":"Stop"}"#, path: path).value
        #expect(result == HookRunner.Outcome(delivered: true, output: nil))
    }

    @Test func attachesTheTerminalLookupInfoToTheEvent() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        let outcome = handle(permissionJSON, path: path, ancestry: { ([4242, 99, 1], "ttys007") })
        let event = try #require(await firstEvent(from: server))
        #expect(event.ancestorPIDs == [4242, 99, 1])
        #expect(event.tty == "ttys007")
        server.cancel(requestID: try #require(event.requestID))
        _ = await outcome.value
    }
}
