import Foundation

/// Adds and removes Claudenotchi's hook entries in a Claude Code `settings.json`,
/// leaving everything else in the file alone.
///
/// Our entries are recognized by the helper's file name (`claudenotchi-hook`), so uninstall works
/// even after the helper moved. The file is parsed, merged and rewritten atomically; a copy of the
/// previous contents is saved next to it before any change. Files that are not valid JSON or have an
/// unexpected `hooks` shape are refused rather than overwritten.
public struct HookInstaller {
    /// Hook events the app listens to.
    public static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "Notification", "PermissionRequest", "Stop", "SessionEnd",
    ]
    public static let helperName = "claudenotchi-hook"
    /// Seconds Claude Code waits for the helper (it normally returns in milliseconds).
    private static let hookTimeout = 10

    public enum Failure: Error, Equatable {
        case invalidJSON(String)
        case unexpectedStructure(String)
        case io(String)
    }

    public struct Result: Equatable {
        public var changed: Bool
        public var backupURL: URL?
    }

    public let settingsURL: URL
    public let helperPath: String
    private let now: () -> Date

    public init(settingsURL: URL, helperPath: String, now: @escaping () -> Date = Date.init) {
        self.settingsURL = settingsURL
        self.helperPath = helperPath
        self.now = now
    }

    private var command: String { "\"\(helperPath)\"" }

    // MARK: Public API

    @discardableResult
    public func install() throws -> Result {
        let (root, original) = try load()
        var updated = root
        var hooks = try hooksObject(in: root)
        for event in Self.events {
            var groups = try groups(hooks[event], event: event)
            groups = removeOurs(from: groups)
            groups.append(["hooks": [["type": "command", "command": command, "timeout": Self.hookTimeout]]])
            hooks[event] = groups
        }
        updated["hooks"] = hooks
        return try save(updated, replacing: root, original: original)
    }

    @discardableResult
    public func uninstall() throws -> Result {
        let (root, original) = try load()
        guard original != nil else { return Result(changed: false, backupURL: nil) }
        var updated = root
        var hooks = try hooksObject(in: root)
        for event in Array(hooks.keys) {
            let cleaned = removeOurs(from: try groups(hooks[event], event: event))
            if cleaned.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = cleaned }
        }
        if hooks.isEmpty { updated.removeValue(forKey: "hooks") } else { updated["hooks"] = hooks }
        return try save(updated, replacing: root, original: original)
    }

    /// True when every event has an entry that runs exactly this installer's helper.
    public func isInstalled() throws -> Bool {
        let (root, original) = try load()
        guard original != nil else { return false }
        let hooks = try hooksObject(in: root)
        for event in Self.events {
            let present = try groups(hooks[event], event: event).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String) == command }
            }
            if !present { return false }
        }
        return true
    }

    // MARK: Reading and writing

    /// The settings file's real location: a symlinked `~/.claude/settings.json` is edited in place.
    private var fileURL: URL { settingsURL.resolvingSymlinksInPath() }

    private func load() throws -> (root: [String: Any], original: Data?) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return ([:], nil) }
        let data: Data
        do { data = try Data(contentsOf: fileURL) } catch { throw Failure.io("cannot read settings: \(error)") }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return ([:], data) }
        let parsed: Any
        do { parsed = try JSONSerialization.jsonObject(with: data) } catch {
            throw Failure.invalidJSON("settings.json is not valid JSON: \(error.localizedDescription)")
        }
        guard let object = parsed as? [String: Any] else {
            throw Failure.unexpectedStructure("settings.json is not a JSON object")
        }
        return (object, data)
    }

    private func save(_ updated: [String: Any], replacing old: [String: Any], original: Data?) throws -> Result {
        // Nothing to do when the file already says what we would write; no rewrite, no backup.
        if original != nil, NSDictionary(dictionary: updated).isEqual(to: old) {
            return Result(changed: false, backupURL: nil)
        }

        var backupURL: URL?
        if let original { backupURL = try writeBackup(original) }

        do {
            var data = try JSONSerialization.data(
                withJSONObject: updated,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            data.append(UInt8(ascii: "\n"))
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw Failure.io("cannot write settings: \(error)")
        }
        return Result(changed: true, backupURL: backupURL)
    }

    /// `settings.json.claudenotchi-backup-20261014-153000`, with `-2`, `-3`... if that name is taken.
    private func writeBackup(_ data: Data) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "\(settingsURL.lastPathComponent).claudenotchi-backup-\(formatter.string(from: now()))"
        let directory = settingsURL.deletingLastPathComponent()
        var candidate = directory.appendingPathComponent(base)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(counter)")
            counter += 1
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: candidate, options: .atomic)
        } catch {
            throw Failure.io("cannot write backup: \(error)")
        }
        return candidate
    }

    // MARK: JSON shape

    private func hooksObject(in root: [String: Any]) throws -> [String: Any] {
        guard let value = root["hooks"] else { return [:] }
        guard let hooks = value as? [String: Any] else {
            throw Failure.unexpectedStructure("\"hooks\" is not an object")
        }
        return hooks
    }

    private func groups(_ value: Any?, event: String) throws -> [[String: Any]] {
        guard let value else { return [] }
        guard let groups = value as? [[String: Any]] else {
            throw Failure.unexpectedStructure("hooks for \(event) are not a list of objects")
        }
        return groups
    }

    /// Drops our entries; groups that held only ours disappear, others keep their remaining hooks.
    private func removeOurs(from groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group in
            guard let inner = group["hooks"] as? [[String: Any]] else { return group }
            let kept = inner.filter { !Self.isOurs($0) }
            if kept.count == inner.count { return group }
            if kept.isEmpty { return nil }
            var copy = group
            copy["hooks"] = kept
            return copy
        }
    }

    /// A command hook whose executable (first word, or the quoted path) is named `claudenotchi-hook`.
    static func isOurs(_ hook: [String: Any]) -> Bool {
        guard (hook["type"] as? String) == "command", let command = hook["command"] as? String else { return false }
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let executable: Substring
        if trimmed.hasPrefix("\"") {
            let rest = trimmed.dropFirst()
            guard let closing = rest.firstIndex(of: "\"") else { return false }
            executable = rest[rest.startIndex..<closing]
        } else {
            executable = trimmed.prefix { $0 != " " }
        }
        return (String(executable) as NSString).lastPathComponent == helperName
    }
}
