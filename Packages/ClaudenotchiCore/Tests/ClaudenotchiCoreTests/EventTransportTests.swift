import Darwin
import Foundation
import Testing
@testable import ClaudenotchiCore

/// Unix socket paths are limited to ~100 bytes, so tests use short paths under /tmp.
private func tempSocketPath() -> String {
    "/tmp/cn-\(UUID().uuidString.prefix(8)).sock"
}

private func collect(_ count: Int, from server: EventServer, timeout: Duration = .seconds(3)) async -> [SessionEvent] {
    await withTaskGroup(of: [SessionEvent].self) { group in
        group.addTask {
            var received: [SessionEvent] = []
            for await event in server.events {
                received.append(event)
                if received.count == count { break }
            }
            return received
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return []
        }
        let first = await group.next() ?? []
        group.cancelAll()
        return first
    }
}

private let sampleTime = Date(timeIntervalSince1970: 5_000)

private func sample(_ type: SessionEvent.EventType = .userPromptSubmit, tool: String? = nil) -> SessionEvent {
    SessionEvent(sessionID: "s1", type: type, tool: tool, cwd: "/tmp/p", timestamp: sampleTime)
}

@Suite struct EventTransportTests {
    @Test func defaultSocketPathLivesInApplicationSupport() {
        let path = SocketPath.default()
        #expect(path.hasSuffix("/Library/Application Support/Claudenotchi/sock"))
    }

    @Test func serverReceivesAnEventFromAClient() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        try EventClient.send(sample(.preToolUse, tool: "Edit"), to: path)

        let events = await collect(1, from: server)
        #expect(events == [sample(.preToolUse, tool: "Edit")])
    }

    @Test func serverDeliversEventsFromSeparateConnectionsInOrder() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        for type in [SessionEvent.EventType.userPromptSubmit, .preToolUse, .postToolUse, .stop] {
            try EventClient.send(sample(type), to: path)
        }

        let events = await collect(4, from: server)
        #expect(events.map(\.type) == [.userPromptSubmit, .preToolUse, .postToolUse, .stop])
    }

    @Test func serverHandlesSeveralLinesOnOneConnection() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        var payload = try sample(.userPromptSubmit).wireLine()
        payload.append(try sample(.stop).wireLine())
        try EventClient.sendRaw(payload, to: path)

        let events = await collect(2, from: server)
        #expect(events.map(\.type) == [.userPromptSubmit, .stop])
    }

    @Test func serverSkipsMalformedLinesAndKeepsGoing() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        var payload = Data("this is not json\n".utf8)
        payload.append(try sample(.stop).wireLine())
        try EventClient.sendRaw(payload, to: path)

        let events = await collect(1, from: server)
        #expect(events.map(\.type) == [.stop])
    }

    @Test func aStoppedServerNeverStealsConnectionsFromTheNextServer() async throws {
        // A stopped server's accept thread must not touch its closed descriptor, which the OS
        // hands to the next server that starts.
        for _ in 0..<150 {
            let old = EventServer(path: tempSocketPath())
            try old.start()
            old.stop()

            let path = tempSocketPath()
            let server = EventServer(path: path)
            try server.start()
            try EventClient.send(sample(.stop), to: path)
            let events = await collect(1, from: server, timeout: .milliseconds(500))
            server.stop()
            #expect(events.map(\.type) == [.stop])
        }
    }

    @Test func serverReplacesAStaleSocketFile() throws {
        let path = tempSocketPath()
        FileManager.default.createFile(atPath: path, contents: Data())
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }
        #expect(throws: Never.self) { try EventClient.send(sample(), to: path) }
    }

    @Test func socketFileIsOwnerOnly() throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }

    @Test func stopRemovesTheSocketAndEndsTheStream() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
        var count = 0
        for await _ in server.events { count += 1 }
        #expect(count == 0)
    }

    @Test func clientThrowsWhenNobodyIsListening() {
        let path = tempSocketPath()
        #expect(throws: EventClient.Failure.self) {
            try EventClient.send(sample(), to: path)
        }
    }

    @Test func serverRejectsPathsThatAreTooLong() {
        let server = EventServer(path: "/tmp/" + String(repeating: "a", count: 200))
        #expect(throws: EventServer.Failure.self) { try server.start() }
    }
}

@Suite struct HookRunnerTests {
    @Test func forwardsAHookPayloadToTheApp() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        let json = #"{"session_id":"abc","cwd":"/tmp/p","hook_event_name":"PreToolUse","tool_name":"Bash"}"#
        let delivered = HookRunner.run(stdin: Data(json.utf8), socketPath: path, now: sampleTime)
        #expect(delivered)

        let events = await collect(1, from: server)
        #expect(events == [SessionEvent(sessionID: "abc", type: .preToolUse, tool: "Bash", cwd: "/tmp/p", timestamp: sampleTime)])
    }

    @Test func staysQuietWhenTheAppIsNotRunning() {
        let json = #"{"session_id":"abc","hook_event_name":"Stop"}"#
        #expect(HookRunner.run(stdin: Data(json.utf8), socketPath: tempSocketPath()) == false)
    }

    @Test func ignoresPayloadsThatAreNotHookJSON() async throws {
        let path = tempSocketPath()
        let server = EventServer(path: path)
        try server.start()
        defer { server.stop() }

        #expect(HookRunner.run(stdin: Data("garbage".utf8), socketPath: path) == false)
        let events = await collect(1, from: server, timeout: .milliseconds(300))
        #expect(events.isEmpty)
    }
}
