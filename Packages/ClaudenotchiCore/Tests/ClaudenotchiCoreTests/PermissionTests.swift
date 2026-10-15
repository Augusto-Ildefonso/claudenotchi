import Foundation
import Testing
@testable import ClaudenotchiCore

@Suite struct PermissionDecisionTests {
    private func hookOutput(_ decision: PermissionDecision) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: decision.hookOutput) as? [String: Any])
    }

    @Test func allowProducesTheDecisionClaudeCodeExpects() throws {
        let output = try hookOutput(.allow)
        let specific = try #require(output["hookSpecificOutput"] as? [String: Any])
        #expect(specific["hookEventName"] as? String == "PermissionRequest")
        let decision = try #require(specific["decision"] as? [String: Any])
        #expect(decision["behavior"] as? String == "allow")
    }

    @Test func denyCarriesTheMessageForClaude() throws {
        let output = try hookOutput(.deny(message: "Denied from Claudenotchi"))
        let decision = try #require((output["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        #expect(decision["behavior"] as? String == "deny")
        #expect(decision["message"] as? String == "Denied from Claudenotchi")
    }

    @Test func denyWithoutAMessageOmitsTheKey() throws {
        let output = try hookOutput(.deny(message: nil))
        let decision = try #require((output["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        #expect(decision["behavior"] as? String == "deny")
        #expect(decision["message"] == nil)
    }

    @Test(arguments: [PermissionDecision.allow, .deny(message: nil), .deny(message: "No, thanks")])
    func wireFormatRoundTrips(decision: PermissionDecision) throws {
        let line = try decision.wireLine()
        #expect(line.last == UInt8(ascii: "\n"))
        #expect(try PermissionDecision(wireLine: line) == decision)
    }

    @Test func unknownBehaviorIsRejected() {
        #expect(throws: (any Error).self) { try PermissionDecision(wireLine: Data(#"{"behavior":"maybe"}"#.utf8)) }
    }

    @Test func garbageIsRejected() {
        #expect(throws: (any Error).self) { try PermissionDecision(wireLine: Data("nope".utf8)) }
    }
}

@Suite struct ToolSummaryTests {
    private func describe(_ tool: String?, _ input: [String: Any]? = nil) -> String {
        ToolSummary.describe(tool: tool, input: input, home: "/Users/ana")
    }

    @Test func bashShowsTheCommand() {
        #expect(describe("Bash", ["command": "xcodebuild -scheme App build"]) == "Bash: xcodebuild -scheme App build")
    }

    @Test func bashCollapsesNewlinesAndRunsOfSpaces() {
        #expect(describe("Bash", ["command": "echo a\n  && echo   b"]) == "Bash: echo a && echo b")
    }

    @Test func longCommandsAreTruncatedWithAnEllipsis() {
        let summary = describe("Bash", ["command": String(repeating: "x", count: 500)])
        #expect(summary.hasPrefix("Bash: xxx"))
        #expect(summary.hasSuffix("…"))
        #expect(summary.count <= 6 + 140 + 1)
    }

    @Test(arguments: ["Edit", "Write", "MultiEdit"])
    func fileToolsShowTheAbbreviatedPath(tool: String) {
        #expect(describe(tool, ["file_path": "/Users/ana/app/main.swift"]) == "\(tool): ~/app/main.swift")
    }

    @Test func notebookEditUsesTheNotebookPath() {
        #expect(describe("NotebookEdit", ["notebook_path": "/Users/ana/n.ipynb"]) == "NotebookEdit: ~/n.ipynb")
    }

    @Test func readGlobAndGrepShowTheirTarget() {
        #expect(describe("Read", ["file_path": "/etc/hosts"]) == "Read: /etc/hosts")
        #expect(describe("Glob", ["pattern": "**/*.swift"]) == "Glob: **/*.swift")
        #expect(describe("Grep", ["pattern": "TODO"]) == "Grep: TODO")
    }

    @Test func webToolsShowTheURLOrQuery() {
        #expect(describe("WebFetch", ["url": "https://example.com"]) == "WebFetch: https://example.com")
        #expect(describe("WebSearch", ["query": "swift testing"]) == "WebSearch: swift testing")
    }

    @Test func taskShowsItsDescription() {
        #expect(describe("Task", ["description": "Explore the repo"]) == "Task: Explore the repo")
    }

    @Test func mcpToolsAreSplitIntoServerAndTool() {
        #expect(describe("mcp__github__list_prs", [:]) == "github: list_prs")
    }

    @Test func unknownToolsShowJustTheirName() {
        #expect(describe("Brand New Tool", ["x": 1]) == "Brand New Tool")
    }

    @Test func missingInputFieldsFallBackToTheToolName() {
        #expect(describe("Bash", [:]) == "Bash")
        #expect(describe("Edit", nil) == "Edit")
    }

    @Test func noToolAtAll() {
        #expect(describe(nil) == "Permission requested")
    }

    // MARK: requests only the terminal can answer

    @Test func aQuestionShowsItsText() {
        let input: [String: Any] = ["questions": [["question": "Cats or dogs?", "header": "Pets", "multiSelect": false]]]
        #expect(describe("AskUserQuestion", input) == "Question: Cats or dogs?")
    }

    @Test func severalQuestionsShowTheFirstAndHowManyMore() {
        let input: [String: Any] = ["questions": [["question": "Cats or dogs?"], ["question": "Tea or coffee?"], ["question": "Sun or rain?"]]]
        #expect(describe("AskUserQuestion", input) == "Question: Cats or dogs? (+2 more)")
    }

    @Test func aQuestionWithoutTextIsStillDescribed() {
        #expect(describe("AskUserQuestion", [:]) == "Claude has a question for you")
        #expect(describe("AskUserQuestion", ["questions": []]) == "Claude has a question for you")
        #expect(describe("AskUserQuestion", nil) == "Claude has a question for you")
    }

    @Test func aPlanIsDescribedAsWaitingForApproval() {
        #expect(describe("ExitPlanMode", ["plan": "1. do things"]) == "Plan ready for your approval")
        #expect(describe("ExitPlanMode", nil) == "Plan ready for your approval")
    }

    @Test(arguments: ["AskUserQuestion", "ExitPlanMode"])
    func theseToolsNeedTheTerminal(tool: String) {
        #expect(ToolSummary.needsTerminal(tool: tool))
    }

    @Test(arguments: ["Bash", "Edit", "Write", "Read", "WebFetch", "Task", "mcp__github__list_prs", "EnterPlanMode", ""])
    func ordinaryToolsCanBeAnsweredFromTheNotch(tool: String) {
        #expect(ToolSummary.needsTerminal(tool: tool) == false)
    }

    @Test func noToolMeansAnOrdinaryRequest() {
        #expect(ToolSummary.needsTerminal(tool: nil) == false)
    }
}

@Suite struct PermissionEventParsingTests {
    let now = Date(timeIntervalSince1970: 1_000)

    @Test func permissionRequestsExpectAReplyAndDescribeTheTool() throws {
        let json = #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"touch a.txt"}}"#
        let event = try SessionEvent(hookJSON: Data(json.utf8), receivedAt: now)
        #expect(event.expectsReply)
        #expect(event.tool == "Bash")
        #expect(event.message == "Bash: touch a.txt")
    }

    // Real Claude Code fires the permission hook for these, but an `allow` does nothing: the question or the
    // plan dialog stays in the terminal. The connection is still held open so the app can tell when the
    // dialog is cancelled (Claude Code kills the waiting hook), but the app never answers it.
    @Test(arguments: [
        ("AskUserQuestion", #"{"questions":[{"question":"Cats or dogs?"}]}"#, "Question: Cats or dogs?"),
        ("ExitPlanMode", #"{"plan":"1. x"}"#, "Plan ready for your approval"),
    ])
    func requestsOnlyTheTerminalCanAnswerAreStillWatched(tool: String, input: String, message: String) throws {
        let json = #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"\#(tool)","tool_input":\#(input)}"#
        let event = try SessionEvent(hookJSON: Data(json.utf8), receivedAt: now)
        #expect(event.type == .permissionRequest)
        #expect(event.expectsReply, "kept open so a cancel can be noticed")
        #expect(event.message == message)
    }

    @Test func otherEventsNeverExpectAReply() throws {
        for name in ["PreToolUse", "PostToolUse", "Stop", "Notification", "SessionStart"] {
            let event = try SessionEvent(hookJSON: Data(#"{"session_id":"s","hook_event_name":"\#(name)"}"#.utf8), receivedAt: now)
            #expect(event.expectsReply == false, "\(name)")
        }
    }

    @Test func notificationKeepsItsOwnMessage() throws {
        let json = #"{"session_id":"s","hook_event_name":"Notification","message":"Claude is waiting for your input"}"#
        let event = try SessionEvent(hookJSON: Data(json.utf8), receivedAt: now)
        #expect(event.message == "Claude is waiting for your input")
    }

    @Test func requestIDAndTerminalInfoSurviveTheWire() throws {
        var event = SessionEvent(sessionID: "s", type: .permissionRequest, tool: "Bash", message: "Bash: ls", timestamp: now, expectsReply: true)
        event.requestID = "req-1"
        event.ancestorPIDs = [4242, 100, 1]
        event.tty = "ttys003"
        let decoded = try SessionEvent(wireLine: event.wireLine())
        #expect(decoded == event)
    }

    @Test func olderWireLinesWithoutTheNewFieldsStillDecode() throws {
        let line = Data(#"{"session_id":"s","type":"stop","ts":5}"#.utf8)
        let event = try SessionEvent(wireLine: line)
        #expect(event.expectsReply == false)
        #expect(event.requestID == nil)
        #expect(event.ancestorPIDs.isEmpty)
        #expect(event.tty == nil)
    }
}
