import Foundation

/// Which Claude Code sessions are open right now, so the app can hide while there are none.
/// A session ends with `SessionEnd`, but a closed terminal window or a crash sends nothing, so the Claude
/// process of each session is remembered and `prune` drops sessions whose process is gone.
public struct SessionRegistry {
    /// Without a known process there is nothing to check; such a session expires after this long with no event.
    public static let silenceLimit: TimeInterval = 30 * 60

    private struct Entry {
        var pid: Int?
        var lastSeen: Date
    }

    private var sessions: [String: Entry] = [:]

    public init() {}

    public var isEmpty: Bool { sessions.isEmpty }
    public var count: Int { sessions.count }

    /// Any event proves the session exists, including one whose start the app missed (it launched later).
    public mutating func handle(_ event: SessionEvent, claudePID: Int?) {
        if event.type == .sessionEnd {
            sessions[event.sessionID] = nil
            return
        }
        var entry = sessions[event.sessionID] ?? Entry(pid: nil, lastSeen: event.timestamp)
        entry.lastSeen = event.timestamp
        if let claudePID { entry.pid = claudePID }
        sessions[event.sessionID] = entry
    }

    public mutating func prune(now: Date, isAlive: (Int) -> Bool) {
        sessions = sessions.filter { _, entry in
            if let pid = entry.pid { return isAlive(pid) }
            return now.timeIntervalSince(entry.lastSeen) < Self.silenceLimit
        }
    }
}
