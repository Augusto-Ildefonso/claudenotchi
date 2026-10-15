import Foundation

/// Keeps a copy of the hook helper at a stable path. Hooks point at that copy, not into the app
/// bundle, so they keep working if the app is moved, updated or run from a translocated location.
public enum HelperDeployer {
    public enum Failure: Error, Equatable {
        case sourceMissing(String)
        case io(String)
    }

    public static func defaultDestination() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claudenotchi/bin")
            .appendingPathComponent(HookInstaller.helperName)
    }

    /// Copies `source` to `destination` unless an identical file is already there.
    /// Returns whether anything was written. The replacement is atomic, so a hook that fires
    /// mid-update never sees a half-written executable.
    @discardableResult
    public static func deploy(source: URL, destination: URL) throws -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: source.path) else { throw Failure.sourceMissing(source.path) }

        let data: Data
        do { data = try Data(contentsOf: source) } catch { throw Failure.io("cannot read helper: \(error)") }
        if let existing = try? Data(contentsOf: destination), existing == data { return false }

        do {
            let directory = destination.deletingLastPathComponent()
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        } catch {
            throw Failure.io("cannot install helper: \(error)")
        }
        return true
    }
}
