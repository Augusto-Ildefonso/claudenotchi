import Darwin
import Foundation

/// Listens on a Unix domain socket for newline-delimited `SessionEvent` JSON written by the hook helper.
/// Malformed lines are dropped; the stream keeps going.
public final class EventServer: @unchecked Sendable {
    public enum Failure: Error, Equatable {
        case pathTooLong
        case socket(String, errno: Int32)
    }

    public let events: AsyncStream<SessionEvent>

    private let path: String
    private let continuation: AsyncStream<SessionEvent>.Continuation
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var wakeRead: Int32 = -1
    private var wakeWrite: Int32 = -1
    /// Signalled when the accept thread has returned, so `stop()` can close the descriptor safely.
    private let acceptLoopFinished = DispatchSemaphore(value: 0)

    public init(path: String) {
        self.path = path
        var captured: AsyncStream<SessionEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        continuation = captured
    }

    public func start() throws {
        guard var address = UnixSocket.address(for: path) else { throw Failure.pathTooLong }

        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        unlink(path)

        let descriptor = UnixSocket.makeStreamSocket()
        guard descriptor >= 0 else { throw Failure.socket("socket", errno: errno) }

        let bound = UnixSocket.withSockaddr(&address) { bind(descriptor, $0, $1) }
        guard bound == 0 else {
            let code = errno
            close(descriptor)
            throw Failure.socket("bind", errno: code)
        }
        chmod(path, 0o600)
        guard listen(descriptor, 16) == 0 else {
            let code = errno
            close(descriptor)
            throw Failure.socket("listen", errno: code)
        }

        var pipeEnds: [Int32] = [-1, -1]
        guard pipe(&pipeEnds) == 0 else {
            let code = errno
            close(descriptor)
            throw Failure.socket("pipe", errno: code)
        }

        lock.lock()
        listener = descriptor
        wakeRead = pipeEnds[0]
        wakeWrite = pipeEnds[1]
        lock.unlock()

        let wake = pipeEnds[0]
        Thread.detachNewThread { [self] in
            acceptLoop(listener: descriptor, wake: wake)
            acceptLoopFinished.signal()
        }
    }

    public func stop() {
        lock.lock()
        let descriptor = listener
        let (readEnd, writeEnd) = (wakeRead, wakeWrite)
        listener = -1
        lock.unlock()
        guard descriptor >= 0 else { return }

        // Wake the accept thread through the pipe, then wait for it to leave. Only then close the
        // descriptors: if the OS reused a closed descriptor number for the next server while a
        // late-starting thread still accepted on it, that thread would steal the new server's connections.
        var byte: UInt8 = 0
        _ = Darwin.write(writeEnd, &byte, 1)
        acceptLoopFinished.wait()
        close(descriptor)
        close(readEnd)
        close(writeEnd)
        unlink(path)
        continuation.finish()
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return listener < 0
    }

    private func acceptLoop(listener descriptor: Int32, wake: Int32) {
        var watched = [
            pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0),
            pollfd(fd: wake, events: Int16(POLLIN), revents: 0),
        ]
        while !isStopped {
            watched[0].revents = 0
            watched[1].revents = 0
            if poll(&watched, 2, -1) < 0 {
                if errno == EINTR { continue }
                return
            }
            if watched[1].revents != 0 { return } // woken by stop()
            if watched[0].revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 { return }
            guard watched[0].revents & Int16(POLLIN) != 0 else { continue }

            let client = accept(descriptor, nil, nil)
            if client < 0 {
                if errno == EINTR || errno == ECONNABORTED || errno == EAGAIN { continue }
                return
            }
            // Read inline, in accept order, so events from consecutive hook invocations are delivered
            // in the order they were sent. The receive timeout stops a stuck client from blocking others.
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            read(from: client)
        }
    }

    private func read(from client: Int32) {
        defer { close(client) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(client, &chunk, chunk.count)
            if count < 0 && errno == EINTR { continue }
            if count <= 0 { break }
            buffer.append(chunk, count: count)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                if let event = try? SessionEvent(wireLine: Data(line)) { continuation.yield(event) }
            }
        }
        if !buffer.isEmpty, let event = try? SessionEvent(wireLine: buffer) { continuation.yield(event) }
    }
}
