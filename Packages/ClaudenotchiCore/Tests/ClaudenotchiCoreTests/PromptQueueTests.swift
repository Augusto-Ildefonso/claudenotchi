import Foundation
import Testing
@testable import ClaudenotchiCore

@Suite struct PromptQueueTests {
    let now = Date(timeIntervalSince1970: 9_000)

    private func prompt(_ id: String, session: String = "s1", message: String = "Bash: ls") -> PendingPrompt {
        PendingPrompt(id: id, sessionID: session, tool: "Bash", message: message, cwd: "/tmp/p", ancestorPIDs: [10, 1], tty: "ttys001")
    }

    private func event(_ type: SessionEvent.EventType, session: String = "s1") -> SessionEvent {
        SessionEvent(sessionID: session, type: type, timestamp: now)
    }

    @Test func startsEmpty() {
        let queue = PromptQueue()
        #expect(queue.current == nil)
        #expect(queue.isEmpty)
    }

    @Test func showsTheOldestPromptFirst() {
        var queue = PromptQueue()
        queue.add(prompt("a"))
        queue.add(prompt("b"))
        #expect(queue.current?.id == "a")
        #expect(queue.count == 2)
    }

    @Test func removingTheCurrentPromptShowsTheNext() {
        var queue = PromptQueue()
        queue.add(prompt("a"))
        queue.add(prompt("b"))
        #expect(queue.remove(id: "a")?.id == "a")
        #expect(queue.current?.id == "b")
    }

    @Test func removingAnUnknownPromptDoesNothing() {
        var queue = PromptQueue()
        queue.add(prompt("a"))
        #expect(queue.remove(id: "zzz") == nil)
        #expect(queue.count == 1)
    }

    @Test func addingTheSamePromptTwiceKeepsOne() {
        var queue = PromptQueue()
        queue.add(prompt("a"))
        queue.add(prompt("a"))
        #expect(queue.count == 1)
    }

    // The user answered in the terminal, or Claude moved on: these events mean the prompt is over.
    @Test(arguments: [SessionEvent.EventType.postToolUse, .postToolUseFailure, .preToolUse, .stop, .userPromptSubmit, .sessionEnd])
    func laterActivityInTheSameSessionResolvesItsPrompts(type: SessionEvent.EventType) {
        var queue = PromptQueue()
        queue.add(prompt("a"))
        queue.add(prompt("b"))
        let resolved = queue.eventArrived(event(type))
        #expect(Set(resolved) == ["a", "b"])
        #expect(queue.isEmpty)
    }

    @Test func otherSessionsAreLeftAlone() {
        var queue = PromptQueue()
        queue.add(prompt("a", session: "s1"))
        queue.add(prompt("b", session: "s2"))
        let resolved = queue.eventArrived(event(.postToolUse, session: "s1"))
        #expect(resolved == ["a"])
        #expect(queue.current?.id == "b")
    }

    @Test(arguments: [SessionEvent.EventType.notification, .sessionStart, .unknown, .permissionRequest])
    func theseEventsDoNotResolveAnything(type: SessionEvent.EventType) {
        var queue = PromptQueue()
        queue.add(prompt("a"))
        #expect(queue.eventArrived(event(type)).isEmpty)
        #expect(queue.count == 1)
    }
}

@Suite struct PendingPromptTests {
    @Test func buildsFromAPermissionEventWithARequestID() throws {
        let event = SessionEvent(
            sessionID: "s9", type: .permissionRequest, tool: "Edit", message: "Edit: ~/a.swift", cwd: "/tmp/p",
            timestamp: Date(timeIntervalSince1970: 1), expectsReply: true, requestID: "req-7", ancestorPIDs: [5, 1], tty: "ttys002"
        )
        let prompt = try #require(PendingPrompt(event: event))
        #expect(prompt.id == "req-7")
        #expect(prompt.sessionID == "s9")
        #expect(prompt.tool == "Edit")
        #expect(prompt.message == "Edit: ~/a.swift")
        #expect(prompt.cwd == "/tmp/p")
        #expect(prompt.ancestorPIDs == [5, 1])
        #expect(prompt.tty == "ttys002")
    }

    @Test func needsARequestIDToBeAnswerable() {
        let event = SessionEvent(sessionID: "s", type: .permissionRequest, timestamp: Date(), expectsReply: true)
        #expect(PendingPrompt(event: event) == nil)
    }

    @Test func fallsBackToAGenericMessage() throws {
        let event = SessionEvent(sessionID: "s", type: .permissionRequest, timestamp: Date(), expectsReply: true, requestID: "r")
        #expect(try #require(PendingPrompt(event: event)).message == "Permission requested")
    }
}
