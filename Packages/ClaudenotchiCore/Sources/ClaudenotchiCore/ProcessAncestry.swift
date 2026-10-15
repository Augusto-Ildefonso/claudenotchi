import Darwin
import Foundation

/// Looks up the processes above the hook helper (Claude Code, the shell, the terminal app) so the app
/// can bring the right terminal forward when you click the notch.
public enum ProcessAncestry {
    private static func info(for pid: Int32) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else {
            return nil
        }
        return info
    }

    public static func parent(of pid: Int32) -> Int32? {
        info(for: pid)?.kp_eproc.e_ppid
    }

    /// `[pid, parent, grandparent, ...]`, stopping before launchd, on a loop, or after `limit` entries.
    /// Empty when `pid` does not exist.
    public static func ancestors(startingAt pid: Int32, limit: Int = 24) -> [Int] {
        var chain: [Int] = []
        var current = pid
        while chain.count < limit, current > 1, !chain.contains(Int(current)), let parent = parent(of: current) {
            chain.append(Int(current))
            current = parent
        }
        return chain
    }

    /// The controlling terminal of a process, such as `ttys003`, or nil when it has none.
    public static func controllingTTY(of pid: Int32) -> String? {
        guard let device = info(for: pid)?.kp_eproc.e_tdev, device != -1 else { return nil }
        guard let name = devname(device, mode_t(S_IFCHR)) else { return nil }
        return String(cString: name)
    }

    /// The command line of a process (`argv`), or nil when it does not exist or may not be read.
    public static func arguments(of pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        let argc = Int(buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        var index = MemoryLayout<Int32>.size
        func skipNULs() { while index < size, buffer[index] == 0 { index += 1 } }
        func nextString() -> String? {
            guard index < size else { return nil }
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            defer { index += 1 }
            return String(decoding: buffer[start..<index], as: UTF8.self)
        }
        _ = nextString() // the executable path
        skipNULs()
        var result: [String] = []
        while result.count < argc, let argument = nextString() { result.append(argument) }
        return result
    }

    /// Whether a command line is Claude Code: the `claude` command itself, or an npm install running it under
    /// `node`. The process *name* is no help: the native install is a file called `2.1.300`.
    public static func looksLikeClaude(arguments: [String]) -> Bool {
        func basename(_ path: String) -> String { path.split(separator: "/").last.map(String.init) ?? path }
        guard let first = arguments.first else { return false }
        if basename(first) == "claude" { return true }
        if basename(first) == "node", arguments.count > 1 {
            return basename(arguments[1]) == "claude" || arguments[1].contains("/claude-code/")
        }
        return false
    }

    /// The Claude Code process nearest to the hook in a chain of ancestors (it runs the hook, maybe through `sh`).
    public static func claudePID(in ancestors: [Int], arguments: (Int) -> [String]? = { arguments(of: Int32($0)) }) -> Int? {
        ancestors.first { looksLikeClaude(arguments: arguments($0) ?? []) }
    }

    /// Whether a process with this id is alive (a finished process nobody has collected yet does not count).
    public static func isRunning(_ pid: Int) -> Bool {
        guard let info = info(for: Int32(pid)) else { return false }
        return info.kp_proc.p_stat != SZOMB
    }

    /// For the running helper: the chain starting at its parent, and the first terminal found along it.
    public static func current() -> (pids: [Int], tty: String?) {
        let pids = ancestors(startingAt: getppid())
        let tty = pids.lazy.compactMap { controllingTTY(of: Int32($0)) }.first
        return (pids, tty)
    }
}
