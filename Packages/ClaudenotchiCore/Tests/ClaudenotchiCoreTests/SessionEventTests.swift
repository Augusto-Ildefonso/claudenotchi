import Foundation
import Testing
@testable import ClaudenotchiCore

@Suite struct SessionEventTests {
    let now = Date(timeIntervalSince1970: 1_000)

    private func event(_ json: String) throws -> SessionEvent {
        try SessionEvent(hookJSON: Data(json.utf8), receivedAt: now)
    }

    @Test func decodesUserPromptSubmit() throws {
        let e = try event(#"{"session_id":"abc","cwd":"/tmp/p","hook_event_name":"UserPromptSubmit","prompt":"hi"}"#)
        #expect(e.sessionID == "abc")
        #expect(e.type == .userPromptSubmit)
        #expect(e.cwd == "/tmp/p")
        #expect(e.timestamp == now)
        #expect(e.tool == nil)
    }

    @Test func capturesToolNameFromPreToolUse() throws {
        let e = try event(#"{"session_id":"abc","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"/a.swift"}}"#)
        #expect(e.type == .preToolUse)
        #expect(e.tool == "Edit")
    }

    @Test func capturesNotificationMessage() throws {
        let e = try event(#"{"session_id":"abc","hook_event_name":"Notification","message":"Claude needs your permission to use Bash"}"#)
        #expect(e.type == .notification)
        #expect(e.message == "Claude needs your permission to use Bash")
    }

    @Test func capturesTheInterruptFlagOfAFailedTool() throws {
        let interrupted = try event(#"{"session_id":"s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","error":"x","is_interrupt":true}"#)
        let failed = try event(#"{"session_id":"s","hook_event_name":"PostToolUseFailure","tool_name":"Bash","error":"x","is_interrupt":false}"#)
        let plain = try event(#"{"session_id":"s","hook_event_name":"Stop"}"#)
        #expect(interrupted.isInterrupt)
        #expect(failed.isInterrupt == false)
        #expect(plain.isInterrupt == false)
    }

    @Test func capturesTranscriptPath() throws {
        let e = try event(#"{"session_id":"abc","hook_event_name":"Stop","transcript_path":"/t/abc.jsonl"}"#)
        #expect(e.transcriptPath == "/t/abc.jsonl")
    }

    @Test(arguments: [
        ("SessionStart", SessionEvent.EventType.sessionStart),
        ("UserPromptSubmit", .userPromptSubmit),
        ("PreToolUse", .preToolUse),
        ("PostToolUse", .postToolUse),
        ("PostToolUseFailure", .postToolUseFailure),
        ("Notification", .notification),
        ("PermissionRequest", .permissionRequest),
        ("Stop", .stop),
        ("SessionEnd", .sessionEnd),
    ])
    func mapsKnownHookNames(name: String, expected: SessionEvent.EventType) throws {
        let e = try event(#"{"session_id":"s","hook_event_name":"\#(name)"}"#)
        #expect(e.type == expected)
    }

    @Test func unknownHookNameBecomesUnknownType() throws {
        let e = try event(#"{"session_id":"s","hook_event_name":"SomethingNew"}"#)
        #expect(e.type == .unknown)
    }

    @Test func missingHookEventNameThrows() {
        #expect(throws: SessionEvent.DecodingFailure.self) {
            try event(#"{"session_id":"s"}"#)
        }
    }

    @Test func invalidJSONThrows() {
        #expect(throws: SessionEvent.DecodingFailure.self) {
            try event("not json")
        }
    }

    @Test func missingSessionIDFallsBackToUnknownSession() throws {
        let e = try event(#"{"hook_event_name":"Stop"}"#)
        #expect(e.sessionID == "unknown")
    }

    @Test func wireLineRoundTrips() throws {
        let original = SessionEvent(
            sessionID: "abc", type: .preToolUse, tool: "Bash", message: nil,
            cwd: "/tmp/p", transcriptPath: "/t.jsonl", timestamp: now, isInterrupt: true
        )
        let line = try original.wireLine()
        #expect(line.last == UInt8(ascii: "\n"))
        let decoded = try SessionEvent(wireLine: line)
        #expect(decoded == original)
    }
}
