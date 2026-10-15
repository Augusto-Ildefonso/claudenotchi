import Foundation

/// The user's answer to a permission prompt.
public enum PermissionDecision: Equatable, Sendable {
    case allow
    case deny(message: String?)

    public struct InvalidReply: Error, Equatable {
        public let reason: String
    }

    /// What the hook helper prints on stdout for Claude Code (PermissionRequest decision control).
    public var hookOutput: Data {
        var decision: [String: Any] = ["behavior": behavior]
        if case .deny(let message?) = self { decision["message"] = message }
        let output: [String: Any] = [
            "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision],
        ]
        // The input is built from literals above, so serialization cannot fail.
        return (try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])) ?? Data()
    }

    // MARK: Wire format (app -> helper), one JSON line

    public func wireLine() throws -> Data {
        var object: [String: Any] = ["behavior": behavior]
        if case .deny(let message?) = self { object["message"] = message }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(UInt8(ascii: "\n"))
        return data
    }

    public init(wireLine: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: wireLine) as? [String: Any],
              let behavior = object["behavior"] as? String else {
            throw InvalidReply(reason: "not a decision")
        }
        switch behavior {
        case "allow": self = .allow
        case "deny": self = .deny(message: object["message"] as? String)
        default: throw InvalidReply(reason: "unknown behavior \(behavior)")
        }
    }

    private var behavior: String {
        switch self {
        case .allow: "allow"
        case .deny: "deny"
        }
    }
}
