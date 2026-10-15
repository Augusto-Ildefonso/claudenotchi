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

    public init(
        sessionID: String, type: EventType, tool: String? = nil, message: String? = nil,
        cwd: String? = nil, transcriptPath: String? = nil, timestamp: Date
    ) {
        self.sessionID = sessionID
        self.type = type
        self.tool = tool
        self.message = message
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case type, tool, message, cwd
        case transcriptPath = "transcript_path"
        case timestamp = "ts"
    }

    /// Builds an event from the JSON Claude Code writes to a hook's stdin.
    public init(hookJSON: Data, receivedAt: Date) throws {
        guard let object = try? JSONSerialization.jsonObject(with: hookJSON) as? [String: Any] else {
            throw DecodingFailure(reason: "hook payload is not a JSON object")
        }
        guard let hookName = object["hook_event_name"] as? String else {
            throw DecodingFailure(reason: "missing hook_event_name")
        }
        self.init(
            sessionID: object["session_id"] as? String ?? "unknown",
            type: EventType(hookName: hookName),
            tool: object["tool_name"] as? String,
            message: object["message"] as? String,
            cwd: object["cwd"] as? String,
            transcriptPath: object["transcript_path"] as? String,
            timestamp: receivedAt
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
