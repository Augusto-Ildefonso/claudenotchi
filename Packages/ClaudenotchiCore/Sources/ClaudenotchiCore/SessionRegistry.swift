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
        /// Whether the session runs in a terminal. A background or headless session (a daemon's, the desktop
        /// app's, `claude -p`) runs the same hooks but is not what the pill is about. nil: not known yet.
        var interactive: Bool?
    }

    private var sessions: [String: Entry] = [:]

    public init() {}

    public var isEmpty: Bool { sessions.isEmpty }
    public var count: Int { sessions.count }

    /// Whether any open session runs in a terminal; this, not `isEmpty`, decides whether the pill shows.
    public var hasInteractiveSession: Bool { sessions.values.contains { $0.interactive == true } }

    /// Stand-in sessions, for a Claude Code that was already running when the app started and so has sent the
    /// app nothing yet, are keyed by process.
    private static let standInPrefix = "process-"

    /// Notes a Claude Code process found running without any hook event from it. Its first real event replaces
    /// this stand-in, and it goes when the process does.
    public mutating func noteRunning(pid: Int, interactive: Bool, now: Date) {
        guard !sessions.values.contains(where: { $0.pid == pid }) else { return }
        sessions["\(Self.standInPrefix)\(pid)"] = Entry(pid: pid, lastSeen: now, interactive: interactive)
    }

    /// Any event proves the session exists, including one whose start the app missed (it launched later).
    public mutating func handle(_ event: SessionEvent, claudePID: Int?, interactive: Bool? = nil) {
        if event.type == .sessionEnd {
            sessions[event.sessionID] = nil
            return
        }
        if let claudePID {
            sessions = sessions.filter { !($0.key.hasPrefix(Self.standInPrefix) && $0.value.pid == claudePID) }
        }
        var entry = sessions[event.sessionID] ?? Entry(pid: nil, lastSeen: event.timestamp, interactive: nil)
        entry.lastSeen = event.timestamp
        if let claudePID { entry.pid = claudePID }
        if let interactive { entry.interactive = interactive } // a helper that ran after claude died knows nothing
        sessions[event.sessionID] = entry
    }

    public mutating func prune(now: Date, isAlive: (Int) -> Bool) {
        sessions = sessions.filter { _, entry in
            if let pid = entry.pid { return isAlive(pid) }
            return now.timeIntervalSince(entry.lastSeen) < Self.silenceLimit
        }
    }
}
