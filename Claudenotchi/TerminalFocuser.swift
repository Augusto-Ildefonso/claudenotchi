import AppKit
import OSLog

/// Brings the terminal that runs Claude Code to the front, and where the terminal supports it,
/// selects the tab showing that session.
enum TerminalFocuser {
    private static let log = Logger(subsystem: "dev.claudenotchi.Claudenotchi", category: "focus")

    /// - Parameters:
    ///   - ancestorPIDs: the hook helper's parent chain; the nearest regular app in it is the terminal.
    ///   - tty: the session's terminal device, e.g. `ttys003`.
    /// - Returns: whether a terminal app was found.
    @discardableResult
    static func focus(ancestorPIDs: [Int], tty: String?) -> Bool {
        guard let app = owningApp(of: ancestorPIDs) else {
            log.info("No terminal app found among \(ancestorPIDs.count) ancestors")
            return false
        }
        log.info("terminal app: \(app.bundleIdentifier ?? "?", privacy: .public) pid \(app.processIdentifier, privacy: .public)")
        // Tab selection also activates the app; fall back to a plain activation.
        if let tty, let script = tabScript(bundleID: app.bundleIdentifier, tty: tty), run(script) { return true }
        raise(app)
        return true
    }

    /// The nearest ancestor that is a regular app: Terminal, iTerm2, Ghostty, VS Code and so on.
    /// Command-line processes in between (Claude Code, the shell) are not apps and are skipped.
    static func owningApp(of pids: [Int]) -> NSRunningApplication? {
        pids.lazy
            .compactMap { NSRunningApplication(processIdentifier: pid_t($0)) }
            .first { $0.activationPolicy == .regular }
    }

    /// Opening the app activates it even though this app never becomes active itself.
    private static func raise(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else {
            app.activate()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { log.error("Could not raise the terminal: \(String(describing: error))") }
        }
    }

    // MARK: Tab selection (best effort, needs the user's OK for Apple Events on first use)

    /// AppleScript that selects the tab or session on `tty`. The tty is restricted to letters and digits
    /// so it can never alter the script.
    static func tabScript(bundleID: String?, tty: String) -> String? {
        guard !tty.isEmpty, tty.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        let device = "/dev/\(tty)"
        switch bundleID {
        case "com.apple.Terminal":
            return """
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(device)" then
                            set selected tab of w to t
                            set frontmost of w to true
                            activate
                            return true
                        end if
                    end repeat
                end repeat
                activate
                return false
            end tell
            """
        case "com.googlecode.iterm2":
            return """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(device)" then
                                select w
                                select t
                                select s
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
                activate
                return false
            end tell
            """
        default:
            return nil
        }
    }

    private static func run(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            log.error("Tab selection failed: \(error)")
            return false
        }
        return true
    }
}
