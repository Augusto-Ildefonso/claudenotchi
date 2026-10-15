import Foundation

/// One-line, human-readable description of a tool call for the permission prompt.
public enum ToolSummary {
    private static let maxDetailLength = 140

    public static func describe(tool: String?, input: [String: Any]?, home: String) -> String {
        guard let tool, !tool.isEmpty else { return "Permission requested" }

        if tool.hasPrefix("mcp__") {
            let parts = tool.components(separatedBy: "__")
            if parts.count >= 3 { return "\(parts[1]): \(parts.dropFirst(2).joined(separator: "__"))" }
            return tool
        }

        let detail: String?
        switch tool {
        case "Bash":
            detail = string("command", in: input).map(collapse)
        case "Edit", "Write", "MultiEdit", "Read":
            detail = string("file_path", in: input).map { PathDisplay.abbreviated($0, home: home) }
        case "NotebookEdit":
            detail = string("notebook_path", in: input).map { PathDisplay.abbreviated($0, home: home) }
        case "Glob", "Grep":
            detail = string("pattern", in: input)
        case "WebFetch":
            detail = string("url", in: input)
        case "WebSearch":
            detail = string("query", in: input)
        case "Task":
            detail = string("description", in: input)
        default:
            detail = nil
        }

        guard let detail, !detail.isEmpty else { return tool }
        return "\(tool): \(truncate(detail))"
    }

    private static func string(_ key: String, in input: [String: Any]?) -> String? {
        input?[key] as? String
    }

    /// Newlines and runs of spaces become single spaces, so a multi-line command fits one line.
    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func truncate(_ text: String) -> String {
        text.count > maxDetailLength ? String(text.prefix(maxDetailLength)) + "…" : text
    }
}
