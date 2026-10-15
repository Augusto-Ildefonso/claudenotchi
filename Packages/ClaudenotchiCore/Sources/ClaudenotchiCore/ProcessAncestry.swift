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

    /// For the running helper: the chain starting at its parent, and the first terminal found along it.
    public static func current() -> (pids: [Int], tty: String?) {
        let pids = ancestors(startingAt: getppid())
        let tty = pids.lazy.compactMap { controllingTTY(of: Int32($0)) }.first
        return (pids, tty)
    }
}
