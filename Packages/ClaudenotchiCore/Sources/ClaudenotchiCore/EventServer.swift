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
    /// Request ids of permission prompts whose helper hung up before an answer was sent
    /// (for example, the user answered in the terminal and Claude Code killed the helper).
    public let cancellations: AsyncStream<String>

    /// A permission request waiting for the user: its open connection and a hang-up watcher.
    private struct PendingConnection {
        let descriptor: Int32
        let source: DispatchSourceRead
    }

    private let path: String
    private let continuation: AsyncStream<SessionEvent>.Continuation
    private let cancellationContinuation: AsyncStream<String>.Continuation
    private var pending: [String: PendingConnection] = [:]
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
        var capturedCancellations: AsyncStream<String>.Continuation!
        cancellations = AsyncStream(bufferingPolicy: .unbounded) { capturedCancellations = $0 }
        cancellationContinuation = capturedCancellations
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

        // Release helpers still waiting for an answer: they see end-of-file and print nothing.
        lock.lock()
        let waiting = pending
        pending = [:]
        lock.unlock()
        for connection in waiting.values { connection.source.cancel() }

        continuation.finish()
        cancellationContinuation.finish()
    }

    // MARK: Permission prompts

    /// Sends the user's answer to the helper waiting on `requestID` and closes the connection.
    /// Returns false when that request is no longer waiting (already answered, cancelled or hung up).
    @discardableResult
    public func reply(to requestID: String, with decision: PermissionDecision) -> Bool {
        guard let line = try? decision.wireLine(), let connection = take(requestID) else { return false }
        let delivered = UnixSocket.writeAll(connection.descriptor, line)
        connection.source.cancel() // closes the descriptor
        return delivered
    }

    /// Releases the helper without an answer, so Claude Code falls back to its own prompt.
    public func cancel(requestID: String) {
        take(requestID)?.source.cancel()
    }

    private func take(_ requestID: String) -> PendingConnection? {
        lock.lock()
        defer { lock.unlock() }
        return pending.removeValue(forKey: requestID)
    }

    /// Keeps `client` open for a reply and publishes the event with its request id.
    private func hold(_ client: Int32, for event: SessionEvent) {
        var event = event
        let id = UUID().uuidString
        event.requestID = id

        let source = DispatchSource.makeReadSource(fileDescriptor: client, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in self?.clientActivity(requestID: id, descriptor: client) }
        source.setCancelHandler { close(client) }

        lock.lock()
        pending[id] = PendingConnection(descriptor: client, source: source)
        lock.unlock()
        source.resume()
        continuation.yield(event)
    }

    /// The helper has nothing more to say; readable means it hung up (or sent something we ignore).
    private func clientActivity(requestID: String, descriptor: Int32) {
        var byte: UInt8 = 0
        let count = Darwin.read(descriptor, &byte, 1)
        if count < 0, errno == EINTR || errno == EAGAIN { return }
        if count > 0 { return }
        if let connection = take(requestID) {
            connection.source.cancel()
            cancellationContinuation.yield(requestID)
        }
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
        var handedOff = false
        defer { if !handedOff { close(client) } }
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
                guard let event = try? SessionEvent(wireLine: Data(line)) else { continue }
                if event.expectsReply {
                    handedOff = true
                    hold(client, for: event)
                    return
                }
                continuation.yield(event)
            }
        }
        if !buffer.isEmpty, let event = try? SessionEvent(wireLine: buffer) { continuation.yield(event) }
    }
}
