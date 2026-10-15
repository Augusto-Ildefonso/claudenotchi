import Darwin
import Foundation

/// Where the app listens and the hook helper connects.
public enum SocketPath {
    /// `~/Library/Application Support/Claudenotchi/sock`, or whatever `CLAUDENOTCHI_SOCKET` names. The override
    /// lets a test instance of the app use its own socket instead of taking over the real one.
    public static func `default`(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let override = environment["CLAUDENOTCHI_SOCKET"], !override.isEmpty { return override }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claudenotchi/sock")
            .path
    }
}

enum UnixSocket {
    /// `sockaddr_un.sun_path` is 104 bytes on Darwin, including the terminating NUL.
    static func address(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count <= capacity else { return nil }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                for (index, byte) in bytes.enumerated() { destination[index] = byte }
            }
        }
        return address
    }

    static func withSockaddr<T>(_ address: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    /// Whether something is accepting connections on the socket at `path`. A file left behind by a killed app
    /// refuses connections, so it counts as not listening.
    static func isListening(at path: String) -> Bool {
        guard var address = address(for: path) else { return false }
        let descriptor = makeStreamSocket()
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        return withSockaddr(&address) { connect(descriptor, $0, $1) } == 0
    }

    static func makeStreamSocket() -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        if descriptor >= 0 {
            var on: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        }
        return descriptor
    }

    /// Writes every byte, retrying on EINTR. Returns false if the peer is gone or another error occurs.
    static func writeAll(_ descriptor: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(descriptor, raw.baseAddress! + offset, raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += written
            }
            return true
        }
    }
}
