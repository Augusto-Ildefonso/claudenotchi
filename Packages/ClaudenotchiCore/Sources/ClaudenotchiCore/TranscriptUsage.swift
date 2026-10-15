import Foundation

/// What a session has used so far, for the expanded pill.
public struct UsageSnapshot: Equatable, Sendable {
    public var model: String?
    /// Tokens in the most recent prompt, i.e. how full the context is.
    public var contextTokens: Int
    public var contextWindow: Int?
    /// Estimated cost in US dollars of the messages whose model has a known price; nil when none does.
    public var costUSD: Double?
    public var inputTokens: Int
    public var outputTokens: Int
    public var messageCount: Int
    /// Messages left out of `costUSD` because their model has no known price.
    public var unpricedMessages: Int

    public init(
        model: String?, contextTokens: Int, contextWindow: Int?, costUSD: Double?,
        inputTokens: Int, outputTokens: Int, messageCount: Int, unpricedMessages: Int
    ) {
        self.model = model
        self.contextTokens = contextTokens
        self.contextWindow = contextWindow
        self.costUSD = costUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.messageCount = messageCount
        self.unpricedMessages = unpricedMessages
    }

    public var contextFraction: Double? {
        guard let window = contextWindow, window > 0, messageCount > 0 else { return nil }
        return Double(contextTokens) / Double(window)
    }

    /// `context 38% · $0.42`, or nil when there is nothing to show.
    public var summary: String? {
        var parts: [String] = []
        if let fraction = contextFraction {
            let percent = fraction * 100
            let text = contextTokens > 0 && percent < 1 ? "<1%" : "\(min(100, Int(percent.rounded())))%"
            parts.append("context \(text)")
        }
        if let cost = costUSD {
            parts.append(Self.format(cost: cost) + (unpricedMessages > 0 ? "+" : ""))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func format(cost: Double) -> String {
        if cost < 0.01 { return "<$0.01" }
        if cost >= 1_000 {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return "$" + (formatter.string(from: NSNumber(value: cost.rounded())) ?? "\(Int(cost.rounded()))")
        }
        return String(format: "$%.2f", cost)
    }
}

/// Accumulates usage from a Claude Code transcript (JSONL), fed in arbitrary chunks.
///
/// Claude Code writes one record per content block of an assistant message, each carrying that message's
/// usage so far, so a message id can appear several times: the last record wins and each message counts once.
/// Subagent ("sidechain") messages cost money but do not define how full the main context is.
public struct TranscriptUsage {
    private struct Record {
        var usage: TokenUsage
        var model: String
        var sidechain: Bool
    }

    private var records: [String: Record] = [:]
    private var lastMainID: String?
    private var lastID: String?
    private var buffer = Data()

    public init() {}

    public mutating func ingest(_ chunk: Data) {
        buffer.append(chunk)
        var start = buffer.startIndex
        while let newline = buffer[start...].firstIndex(of: UInt8(ascii: "\n")) {
            consume(line: buffer[start..<newline])
            start = buffer.index(after: newline)
        }
        buffer.removeSubrange(buffer.startIndex..<start)
    }

    private static let usageMarker = Data("\"usage\"".utf8)

    private mutating func consume(line: Data) {
        // Most lines are not assistant messages; skip them without decoding.
        guard line.range(of: Self.usageMarker) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let id = message["id"] as? String,
              let model = message["model"] as? String, !model.hasPrefix("<"),
              let usage = message["usage"] as? [String: Any] else { return }

        func count(_ key: String, in dictionary: [String: Any]) -> Int { (dictionary[key] as? NSNumber)?.intValue ?? 0 }
        let creation = count("cache_creation_input_tokens", in: usage)
        var write5m = creation
        var write1h = 0
        if let breakdown = usage["cache_creation"] as? [String: Any] {
            write5m = count("ephemeral_5m_input_tokens", in: breakdown)
            write1h = count("ephemeral_1h_input_tokens", in: breakdown)
        }
        let sidechain = object["isSidechain"] as? Bool ?? false
        records[id] = Record(
            usage: TokenUsage(
                input: count("input_tokens", in: usage), output: count("output_tokens", in: usage),
                cacheRead: count("cache_read_input_tokens", in: usage), cacheWrite5m: write5m, cacheWrite1h: write1h
            ),
            model: model, sidechain: sidechain
        )
        lastID = id
        if !sidechain { lastMainID = id }
    }

    public var snapshot: UsageSnapshot {
        var input = 0, output = 0, unpriced = 0
        var cost: Double?
        for record in records.values {
            input += record.usage.input
            output += record.usage.output
            if let pricing = ModelCatalog.pricing(for: record.model) {
                cost = (cost ?? 0) + pricing.cost(for: record.usage)
            } else {
                unpriced += 1
            }
        }
        let main = lastMainID.flatMap { records[$0] }
        return UsageSnapshot(
            model: (main ?? lastID.flatMap { records[$0] })?.model,
            contextTokens: main?.usage.promptTokens ?? 0,
            contextWindow: main.flatMap { ModelCatalog.contextWindow(for: $0.model) },
            costUSD: cost,
            inputTokens: input, outputTokens: output,
            messageCount: records.count, unpricedMessages: unpriced
        )
    }
}

/// Reads a transcript file incrementally: each `refresh()` parses only the bytes added since the last one,
/// so a transcript of tens of megabytes is read once.
public final class UsageTracker: @unchecked Sendable {
    private let path: String
    private let lock = NSLock()
    private var transcript = TranscriptUsage()
    private var offset: UInt64 = 0

    public init(path: String) {
        self.path = path
    }

    /// How far into the file we have read.
    public var bytesRead: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return offset
    }

    @discardableResult
    public func refresh() -> UsageSnapshot {
        lock.lock()
        defer { lock.unlock() }
        guard let handle = FileHandle(forReadingAtPath: path) else { return transcript.snapshot }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset { // rewritten shorter: start over
            transcript = TranscriptUsage()
            offset = 0
        }
        guard size > offset else { return transcript.snapshot }

        try? handle.seek(toOffset: offset)
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            transcript.ingest(chunk)
            offset += UInt64(chunk.count)
        }
        return transcript.snapshot
    }
}
