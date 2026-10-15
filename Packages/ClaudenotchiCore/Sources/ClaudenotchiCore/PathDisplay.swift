/// Formats paths for the small expanded pill.
public enum PathDisplay {
    /// `/Users/ana/Projects/app` -> `~/Projects/app` when `home` is `/Users/ana`.
    public static func abbreviated(_ path: String, home: String) -> String {
        var home = home
        while home.count > 1, home.hasSuffix("/") { home.removeLast() }
        guard !home.isEmpty else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
