import Foundation

/// One Claude Code hook invocation, normalized for the app.
/// Carries `sessionID` so multiple sessions can be supported later.
public struct SessionEvent: Equatable, Sendable, Codable {
    public enum EventType: String, Sendable, Codable, CaseIterable {
        case sessionStart, userPromptSubmit, preToolUse, postToolUse, postToolUseFailure
        case notification, permissionRequest, stop, sessionEnd
        case unknown

        init(hookName: String) {
            switch hookName {
            case "SessionStart": self = .sessionStart
            case "UserPromptSubmit": self = .userPromptSubmit
            case "PreToolUse": self = .preToolUse
            case "PostToolUse": self = .postToolUse
            case "PostToolUseFailure": self = .postToolUseFailure
            case "Notification": self = .notification
            case "PermissionRequest": self = .permissionRequest
            case "Stop": self = .stop
            case "SessionEnd": self = .sessionEnd
            default: self = .unknown
            }
        }
    }

    public struct DecodingFailure: Error, Equatable {
        public let reason: String
    }

    public var sessionID: String
    public var type: EventType
    public var tool: String?
    public var message: String?
    public var cwd: String?
    public var transcriptPath: String?
    public var timestamp: Date
    /// True when a failed tool was stopped by the user (Esc), which is not an error to show.
    public var isInterrupt: Bool
    /// True when the sender waits for a `PermissionDecision` on the same connection (permission prompts).
    public var expectsReply: Bool
    /// Assigned by the server to events that expect a reply; pass it to `EventServer.reply`.
    public var requestID: String?
    /// Process ids from the hook helper's parent upward, used to find the terminal app.
    public var ancestorPIDs: [Int]
    /// Controlling terminal of the session, e.g. `ttys003`.
    public var tty: String?
    /// For notifications: why Claude Code sent it (`permission_prompt`, `idle_prompt`, `elicitation_dialog`, ...).
    public var notificationType: String?

    public init(
        sessionID: String, type: EventType, tool: String? = nil, message: String? = nil,
        cwd: String? = nil, transcriptPath: String? = nil, timestamp: Date, isInterrupt: Bool = false,
        expectsReply: Bool = false, requestID: String? = nil, ancestorPIDs: [Int] = [], tty: String? = nil,
        notificationType: String? = nil
    ) {
        self.sessionID = sessionID
        self.type = type
        self.tool = tool
        self.message = message
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.timestamp = timestamp
        self.isInterrupt = isInterrupt
        self.expectsReply = expectsReply
        self.requestID = requestID
        self.ancestorPIDs = ancestorPIDs
        self.tty = tty
        self.notificationType = notificationType
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case type, tool, message, cwd
        case transcriptPath = "transcript_path"
        case timestamp = "ts"
        case isInterrupt = "interrupt"
        case expectsReply = "reply"
        case requestID = "request_id"
        case ancestorPIDs = "ancestors"
        case tty
        case notificationType = "ntype"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(String.self, forKey: .sessionID)
        type = try c.decode(EventType.self, forKey: .type)
        tool = try c.decodeIfPresent(String.self, forKey: .tool)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        transcriptPath = try c.decodeIfPresent(String.self, forKey: .transcriptPath)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        isInterrupt = try c.decodeIfPresent(Bool.self, forKey: .isInterrupt) ?? false
        expectsReply = try c.decodeIfPresent(Bool.self, forKey: .expectsReply) ?? false
        requestID = try c.decodeIfPresent(String.self, forKey: .requestID)
        ancestorPIDs = try c.decodeIfPresent([Int].self, forKey: .ancestorPIDs) ?? []
        tty = try c.decodeIfPresent(String.self, forKey: .tty)
        notificationType = try c.decodeIfPresent(String.self, forKey: .notificationType)
    }

    /// Builds an event from the JSON Claude Code writes to a hook's stdin.
    public init(hookJSON: Data, receivedAt: Date) throws {
        guard let object = try? JSONSerialization.jsonObject(with: hookJSON) as? [String: Any] else {
            throw DecodingFailure(reason: "hook payload is not a JSON object")
        }
        guard let hookName = object["hook_event_name"] as? String else {
            throw DecodingFailure(reason: "missing hook_event_name")
        }
        let type = EventType(hookName: hookName)
        let tool = object["tool_name"] as? String
        var message = object["message"] as? String
        if type == .permissionRequest, message == nil {
            message = ToolSummary.describe(
                tool: tool, input: object["tool_input"] as? [String: Any], home: NSHomeDirectory()
            )
        }
        self.init(
            sessionID: object["session_id"] as? String ?? "unknown",
            type: type,
            tool: tool,
            message: message,
            cwd: object["cwd"] as? String,
            transcriptPath: object["transcript_path"] as? String,
            timestamp: receivedAt,
            isInterrupt: object["is_interrupt"] as? Bool ?? false,
            // Every permission request holds its connection open. Ones the notch cannot answer (see
            // ToolSummary.needsTerminal) are only watched: Claude Code kills the hook when the dialog is cancelled.
            expectsReply: type == .permissionRequest,
            notificationType: object["notification_type"] as? String
        )
    }

    // MARK: Wire format (newline-delimited JSON over the Unix socket)

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    public func wireLine() throws -> Data {
        var data = try Self.encoder.encode(self)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    public init(wireLine: Data) throws {
        do {
            self = try Self.decoder.decode(SessionEvent.self, from: wireLine)
        } catch {
            throw DecodingFailure(reason: "invalid wire line: \(error)")
        }
    }
}
