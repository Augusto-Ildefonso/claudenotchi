import ClaudenotchiCore
import Foundation
import Observation
import OSLog

/// Installs and removes Claudenotchi's hooks in Claude Code's `settings.json`, and reports the result
/// for the menu. The embedded helper is first copied to a stable path so hooks survive the app moving.
@Observable
final class HookSetup {
    enum Status: Equatable {
        case installed
        case notInstalled
        case failed(String)
    }

    /// Set when the user removes the hooks, so launching the app does not quietly put them back.
    static let optedOutKey = "hooksUserOptedOut"
    /// Overrides the settings file, e.g. `-hooksSettingsPath /tmp/settings.json` on the command line.
    static let settingsPathKey = "hooksSettingsPath"

    private(set) var status: Status = .notInstalled

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let log = Logger(subsystem: "dev.claudenotchi.Claudenotchi", category: "hooks")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Where Claude Code reads user settings: `$CLAUDE_CONFIG_DIR/settings.json`, else `~/.claude/settings.json`.
    var settingsURL: URL {
        if let override = defaults.string(forKey: Self.settingsPathKey), !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        if let directory = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !directory.isEmpty {
            return URL(fileURLWithPath: directory).appendingPathComponent("settings.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    private var embeddedHelper: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(HookInstaller.helperName)")
    }

    /// On launch: keep an installed helper current, and install the hooks unless the user removed them.
    func start() {
        refresh()
        if status == .installed {
            deployHelper() // pick up a newer helper after an app update
        } else if !defaults.bool(forKey: Self.optedOutKey) {
            install()
        }
    }

    func install() {
        do {
            let helper = try deployHelper()
            let result = try HookInstaller(settingsURL: settingsURL, helperPath: helper.path).install()
            defaults.set(false, forKey: Self.optedOutKey)
            log.info("Hooks installed in \(self.settingsURL.path), backup: \(result.backupURL?.path ?? "none")")
            status = .installed
        } catch {
            fail(error)
        }
    }

    func uninstall() {
        do {
            let result = try HookInstaller(settingsURL: settingsURL, helperPath: HelperDeployer.defaultDestination().path).uninstall()
            defaults.set(true, forKey: Self.optedOutKey)
            log.info("Hooks removed from \(self.settingsURL.path), backup: \(result.backupURL?.path ?? "none")")
            status = .notInstalled
        } catch {
            fail(error)
        }
    }

    private func refresh() {
        do {
            let installer = HookInstaller(settingsURL: settingsURL, helperPath: HelperDeployer.defaultDestination().path)
            status = try installer.isInstalled() ? .installed : .notInstalled
        } catch {
            fail(error)
        }
    }

    @discardableResult
    private func deployHelper() -> URL {
        let destination = HelperDeployer.defaultDestination()
        do {
            try HelperDeployer.deploy(source: embeddedHelper, destination: destination)
        } catch {
            fail(error)
        }
        return destination
    }

    private func fail(_ error: Error) {
        log.error("Hook setup failed: \(String(describing: error))")
        status = .failed(Self.describe(error))
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case HookInstaller.Failure.invalidJSON(let detail): "settings.json is not valid JSON, so it was left alone. \(detail)"
        case HookInstaller.Failure.unexpectedStructure(let detail): "settings.json has an unexpected shape, so it was left alone. \(detail)"
        case HookInstaller.Failure.io(let detail): detail
        case HelperDeployer.Failure.sourceMissing: "The hook helper is missing from the app bundle."
        case HelperDeployer.Failure.io(let detail): detail
        default: String(describing: error)
        }
    }
}
