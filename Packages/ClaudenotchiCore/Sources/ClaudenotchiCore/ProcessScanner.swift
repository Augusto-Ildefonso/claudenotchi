import Darwin
import Foundation

/// A Claude Code process found running in a terminal.
public struct RunningClaude: Equatable, Sendable {
    public let pid: Int
    /// The process, its parent, and so on up to the terminal app; what click-to-focus needs.
    public let chain: [Int]
    public let tty: String?
}

/// Finds Claude Code sessions that were already running when the app started. The app learns about a session from
/// its hook events, so one that is idle would otherwise stay unknown until it next does something.
public enum ProcessScanner {
    public static func findTerminalSessions(
        pids: [Int],
        parent: (Int) -> Int?,
        arguments: (Int) -> [String]?,
        isRegularApp: (Int) -> Bool,
        name: (Int) -> String?,
        tty: (Int) -> String?
    ) -> [RunningClaude] {
        func isClaude(_ pid: Int) -> Bool { ProcessAncestry.looksLikeClaude(arguments: arguments(pid) ?? []) }
        var found: [RunningClaude] = []
        for pid in pids.sorted() where isClaude(pid) {
            // A claude started by a claude (a helper, a subcommand) is part of that session, not another one.
            if let up = parent(pid), isClaude(up) { continue }
            var chain: [Int] = []
            var current = pid
            while chain.count < 24, current > 1, !chain.contains(current) {
                chain.append(current)
                guard let up = parent(current) else { break }
                current = up
            }
            // Background sessions (a daemon's, the desktop app's) have no terminal above them.
            guard ProcessAncestry.isAttachedToTerminal(ancestors: chain, isRegularApp: isRegularApp, name: name) else { continue }
            found.append(RunningClaude(pid: pid, chain: chain, tty: tty(pid)))
        }
        return found
    }

    /// The Claude Code sessions running in a terminal on this Mac right now.
    public static func findTerminalSessions(isRegularApp: (Int) -> Bool) -> [RunningClaude] {
        findTerminalSessions(
            pids: allPIDs(),
            parent: { ProcessAncestry.parent(of: Int32($0)).map(Int.init) },
            arguments: { ProcessAncestry.arguments(of: Int32($0)) },
            isRegularApp: isRegularApp,
            name: { ProcessAncestry.name(of: Int32($0)) },
            tty: { ProcessAncestry.controllingTTY(of: Int32($0)) }
        )
    }

    public static func allPIDs() -> [Int] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // The table can grow between the two calls; leave some room.
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 32)
        var bytes = buffer.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &buffer, &bytes, nil, 0) == 0 else { return [] }
        return buffer.prefix(bytes / MemoryLayout<kinfo_proc>.stride).map { Int($0.kp_proc.p_pid) }.filter { $0 > 0 }
    }
}
