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

        var offset = 0
        try data.withUnsafeBytes { raw in
            while offset < raw.count {
                let written = Darwin.write(descriptor, raw.baseAddress! + offset, raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw Failure.write(errno: errno)
                }
                offset += written
            }
        }
    }
}
