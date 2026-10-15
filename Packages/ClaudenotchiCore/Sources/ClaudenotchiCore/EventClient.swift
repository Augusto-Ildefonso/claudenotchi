import Darwin
import Foundation

/// Connects to the app's socket and writes events. Used by the hook helper.
public enum EventClient {
    public enum Failure: Error, Equatable {
        case pathTooLong
        case connect(errno: Int32)
        case write(errno: Int32)
    }

    public static func send(_ event: SessionEvent, to path: String) throws {
        try sendRaw(try event.wireLine(), to: path)
    }

    static func sendRaw(_ data: Data, to path: String) throws {
        guard var address = UnixSocket.address(for: path) else { throw Failure.pathTooLong }
        let descriptor = UnixSocket.makeStreamSocket()
        guard descriptor >= 0 else { throw Failure.connect(errno: errno) }
        defer { close(descriptor) }

        let connected = UnixSocket.withSockaddr(&address) { connect(descriptor, $0, $1) }
        guard connected == 0 else { throw Failure.connect(errno: errno) }

        guard UnixSocket.writeAll(descriptor, data) else { throw Failure.write(errno: errno) }
    }

    /// Sends a permission request and blocks until the app answers on the same connection.
    /// Returns nil when the app closes the connection without an answer (cancelled, or shutting down).
    public static func sendAndAwaitReply(_ event: SessionEvent, to path: String) throws -> PermissionDecision? {
        guard var address = UnixSocket.address(for: path) else { throw Failure.pathTooLong }
        let descriptor = UnixSocket.makeStreamSocket()
        guard descriptor >= 0 else { throw Failure.connect(errno: errno) }
        defer { close(descriptor) }

        let connected = UnixSocket.withSockaddr(&address) { connect(descriptor, $0, $1) }
        guard connected == 0 else { throw Failure.connect(errno: errno) }
        guard UnixSocket.writeAll(descriptor, try event.wireLine()) else { throw Failure.write(errno: errno) }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = Darwin.read(descriptor, &chunk, chunk.count)
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if count == 0 { return nil } // the app hung up without answering
            buffer.append(chunk, count: count)
            if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                return try? PermissionDecision(wireLine: Data(buffer[buffer.startIndex..<newline]))
            }
        }
    }
}
