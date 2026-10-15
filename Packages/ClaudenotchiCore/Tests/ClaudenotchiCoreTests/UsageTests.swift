import Foundation
import Testing
@testable import ClaudenotchiCore

/// Builds one transcript line the way Claude Code writes assistant messages.
private func assistant(
    id: String, model: String = "claude-sonnet-5-5", input: Int = 0, output: Int = 0, cacheRead: Int = 0,
    cacheWrite: Int = 0, write5m: Int? = nil, write1h: Int? = nil, sidechain: Bool = false
) -> String {
    var usage: [String: Any] = [
        "input_tokens": input, "output_tokens": output,
        "cache_read_input_tokens": cacheRead, "cache_creation_input_tokens": cacheWrite,
    ]
    if write5m != nil || write1h != nil {
        usage["cache_creation"] = ["ephemeral_5m_input_tokens": write5m ?? 0, "ephemeral_1h_input_tokens": write1h ?? 0]
    }
    let record: [String: Any] = [
        "type": "assistant", "isSidechain": sidechain,
        "message": ["id": id, "model": model, "role": "assistant", "content": [], "usage": usage],
    ]
    return String(decoding: try! JSONSerialization.data(withJSONObject: record), as: UTF8.self)
}

private func usage(from lines: [String]) -> UsageSnapshot {
    var transcript = TranscriptUsage()
    transcript.ingest(Data((lines.joined(separator: "\n") + "\n").utf8))
    return transcript.snapshot
}

@Suite struct ModelCatalogTests {
    @Test func knowsTheCurrentModelsPrices() {
        let sonnet = ModelCatalog.pricing(for: "claude-sonnet-5-5")
        #expect(sonnet?.inputPerMTok == 2 && sonnet?.outputPerMTok == 10 && sonnet?.cacheReadPerMTok == 0.2)
        let opus = ModelCatalog.pricing(for: "claude-opus-5-5")
        #expect(opus?.inputPerMTok == 4 && opus?.outputPerMTok == 20 && opus?.cacheReadPerMTok == 0.2)
        let fable = ModelCatalog.pricing(for: "claude-fable-5-1")
        #expect(fable?.inputPerMTok == 10 && fable?.outputPerMTok == 50 && fable?.cacheReadPerMTok == 0.25)
    }

    @Test func cacheWritesCost125xAnd2xTheInputPrice() {
        let sonnet = try! #require(ModelCatalog.pricing(for: "claude-sonnet-5-5"))
        #expect(sonnet.cacheWrite5mPerMTok == 2.5)
        #expect(sonnet.cacheWrite1hPerMTok == 4)
    }

    @Test func theOneMillionSuffixAndDateSuffixesAreIgnored() {
        #expect(ModelCatalog.canonical("claude-opus-5-5[1m]") == "claude-opus-5-5")
        #expect(ModelCatalog.canonical("Claude-Opus-4-6-20251101") == "claude-opus-4-6")
        #expect(ModelCatalog.canonical("claude-haiku-4-5@20251001") == "claude-haiku-4-5")
        #expect(ModelCatalog.pricing(for: "claude-opus-5-5[1m]") == ModelCatalog.pricing(for: "claude-opus-5-5"))
    }

    @Test func contextWindows() {
        #expect(ModelCatalog.contextWindow(for: "claude-sonnet-5-5") == 1_000_000)
        #expect(ModelCatalog.contextWindow(for: "claude-opus-5-5[1m]") == 1_000_000)
        #expect(ModelCatalog.contextWindow(for: "claude-haiku-4-5") == 200_000)
    }

    @Test func unknownModelsHaveNeitherPriceNorWindow() {
        #expect(ModelCatalog.pricing(for: "claude-future-9") == nil)
        #expect(ModelCatalog.contextWindow(for: "claude-future-9") == nil)
        #expect(ModelCatalog.pricing(for: "") == nil)
    }

    @Test func costAddsUpEveryKindOfToken() throws {
        let sonnet = try #require(ModelCatalog.pricing(for: "claude-sonnet-5-5"))
        let tokens = TokenUsage(input: 1_000, output: 500, cacheRead: 10_000, cacheWrite5m: 2_000, cacheWrite1h: 0)
        // 1000*2 + 500*10 + 10000*0.2 + 2000*2.5 = 2000 + 5000 + 2000 + 5000 = 14000 / 1e6
        #expect(abs(sonnet.cost(for: tokens) - 0.014) < 1e-9)
    }

    @Test func oneHourCacheWritesCostDouble() throws {
        let sonnet = try #require(ModelCatalog.pricing(for: "claude-sonnet-5-5"))
        let tokens = TokenUsage(input: 0, output: 0, cacheRead: 0, cacheWrite5m: 0, cacheWrite1h: 1_000_000)
        #expect(abs(sonnet.cost(for: tokens) - 4) < 1e-9)
    }

    @Test func haikuPricesStepUpForPromptsOver100KTokens() throws {
        let haiku = try #require(ModelCatalog.pricing(for: "claude-haiku-5-5"))
        let small = TokenUsage(input: 50_000, output: 1_000_000, cacheRead: 0, cacheWrite5m: 0, cacheWrite1h: 0)
        let large = TokenUsage(input: 200_000, output: 1_000_000, cacheRead: 0, cacheWrite5m: 0, cacheWrite1h: 0)
        #expect(abs(haiku.cost(for: small) - (50_000 * 0.10 / 1e6 + 0.50)) < 1e-9)
        #expect(abs(haiku.cost(for: large) - (200_000 * 0.50 / 1e6 + 2.50)) < 1e-9)
    }
}

@Suite struct TranscriptUsageTests {
    @Test func aSingleMessageIsCounted() {
        let snap = usage(from: [assistant(id: "m1", input: 1_000, output: 500, cacheRead: 10_000, cacheWrite: 2_000)])
        #expect(snap.messageCount == 1)
        #expect(snap.inputTokens == 1_000 && snap.outputTokens == 500)
        #expect(abs((snap.costUSD ?? 0) - 0.014) < 1e-9)
        #expect(snap.model == "claude-sonnet-5-5")
    }

    @Test func contextIsEverythingInTheLatestPrompt() throws {
        let snap = usage(from: [assistant(id: "m1", input: 2, output: 835, cacheRead: 755_071, cacheWrite: 886)])
        #expect(snap.contextTokens == 755_959)
        let fraction = try #require(snap.contextFraction)
        #expect(abs(fraction - 0.755959) < 1e-9)
    }

    @Test func theLatestMessageDefinesTheContext() {
        let snap = usage(from: [
            assistant(id: "m1", input: 100, cacheRead: 50_000),
            assistant(id: "m2", input: 100, cacheRead: 80_000),
        ])
        #expect(snap.contextTokens == 80_100)
    }

    @Test func repeatedRecordsOfOneMessageCountOnceAndTheLastWins() {
        // Claude Code writes one record per content block, all carrying the message's usage so far.
        let snap = usage(from: [
            assistant(id: "m1", input: 10, output: 5, cacheRead: 1_000),
            assistant(id: "m1", input: 10, output: 40, cacheRead: 1_000),
            assistant(id: "m1", input: 10, output: 90, cacheRead: 1_000),
        ])
        #expect(snap.messageCount == 1)
        #expect(snap.outputTokens == 90)
    }

    @Test func differentMessagesAdd() {
        let snap = usage(from: [
            assistant(id: "m1", input: 100, output: 10),
            assistant(id: "m2", input: 200, output: 20),
        ])
        #expect(snap.inputTokens == 300 && snap.outputTokens == 30 && snap.messageCount == 2)
    }

    @Test func theCacheWriteBreakdownIsUsedWhenPresent() {
        let snap = usage(from: [assistant(id: "m1", cacheWrite: 1_000_000, write5m: 0, write1h: 1_000_000)])
        #expect(abs((snap.costUSD ?? 0) - 4) < 1e-9, "1h writes cost 2x input: 1M * $4")
    }

    @Test func withoutABreakdownCacheWritesAreFiveMinuteWrites() {
        let snap = usage(from: [assistant(id: "m1", cacheWrite: 1_000_000)])
        #expect(abs((snap.costUSD ?? 0) - 2.5) < 1e-9)
    }

    @Test func mixedModelsArePricedEach() {
        let snap = usage(from: [
            assistant(id: "m1", model: "claude-sonnet-5-5", output: 1_000_000),   // $10
            assistant(id: "m2", model: "claude-opus-5-5", output: 1_000_000),     // $20
        ])
        #expect(abs((snap.costUSD ?? 0) - 30) < 1e-9)
    }

    @Test func anUnknownModelIsCountedButNotPriced() {
        let snap = usage(from: [
            assistant(id: "m1", model: "claude-sonnet-5-5", output: 1_000_000),
            assistant(id: "m2", model: "claude-future-9", output: 1_000_000),
        ])
        #expect(abs((snap.costUSD ?? 0) - 10) < 1e-9)
        #expect(snap.unpricedMessages == 1)
        #expect(snap.outputTokens == 2_000_000, "tokens are still counted")
    }

    @Test func anUnknownModelHasNoContextPercent() {
        let snap = usage(from: [assistant(id: "m1", model: "claude-future-9", input: 5_000)])
        #expect(snap.contextTokens == 5_000)
        #expect(snap.contextFraction == nil)
    }

    @Test func subagentMessagesCostMoneyButDoNotDefineTheContext() {
        let snap = usage(from: [
            assistant(id: "main", input: 10, cacheRead: 40_000),
            assistant(id: "side", input: 10, cacheRead: 900_000, sidechain: true),
        ])
        #expect(snap.contextTokens == 40_010)
        #expect(snap.messageCount == 2)
    }

    @Test func otherRecordsAndGarbageAreIgnored() {
        let snap = usage(from: [
            #"{"type":"user","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"system","subtype":"x"}"#,
            "this is not json",
            #"{"type":"assistant","message":{"id":"x","model":"claude-sonnet-5-5"}}"#,   // no usage
            assistant(id: "m1", input: 7),
        ])
        #expect(snap.messageCount == 1 && snap.inputTokens == 7)
    }

    @Test func syntheticMessagesAreIgnored() {
        let snap = usage(from: [assistant(id: "s", model: "<synthetic>", input: 5), assistant(id: "m1", input: 7)])
        #expect(snap.messageCount == 1)
    }

    @Test func aLineSplitAcrossChunksIsReassembled() {
        let line = assistant(id: "m1", input: 123, output: 45) + "\n"
        let bytes = Array(line.utf8)
        var transcript = TranscriptUsage()
        transcript.ingest(Data(bytes[0..<30]))
        #expect(transcript.snapshot.messageCount == 0, "half a line is not a message yet")
        transcript.ingest(Data(bytes[30...]))
        #expect(transcript.snapshot.inputTokens == 123 && transcript.snapshot.outputTokens == 45)
    }

    @Test func aLastLineWithoutANewlineWaitsForItsEnd() {
        var transcript = TranscriptUsage()
        transcript.ingest(Data(assistant(id: "m1", input: 9).utf8))
        #expect(transcript.snapshot.messageCount == 0)
        transcript.ingest(Data("\n".utf8))
        #expect(transcript.snapshot.messageCount == 1)
    }

    @Test func anEmptyTranscriptHasNothingToShow() {
        let snap = TranscriptUsage().snapshot
        #expect(snap.messageCount == 0 && snap.contextFraction == nil && snap.costUSD == nil && snap.model == nil)
    }
}

@Suite struct UsageTrackerTests {
    private func makeFile(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cn-usage-\(UUID().uuidString).jsonl")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        return url
    }

    private func append(_ line: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))
    }

    @Test func readsAFile() throws {
        let url = try makeFile([assistant(id: "m1", input: 100, output: 10)])
        let tracker = UsageTracker(path: url.path)
        #expect(tracker.refresh().inputTokens == 100)
    }

    @Test func readsOnlyWhatWasAppendedSinceTheLastRefresh() throws {
        let url = try makeFile([assistant(id: "m1", input: 100)])
        let tracker = UsageTracker(path: url.path)
        _ = tracker.refresh()
        let before = tracker.bytesRead
        try append(assistant(id: "m2", input: 50), to: url)
        let snap = tracker.refresh()
        #expect(snap.inputTokens == 150 && snap.messageCount == 2)
        #expect(tracker.bytesRead > before)
        // nothing new: no re-read
        let again = tracker.refresh()
        #expect(again == snap)
    }

    @Test func aFileThatShrinksStartsOver() throws {
        let url = try makeFile([assistant(id: "m1", input: 100), assistant(id: "m2", input: 100)])
        let tracker = UsageTracker(path: url.path)
        #expect(tracker.refresh().inputTokens == 200)
        try Data((assistant(id: "n1", input: 7) + "\n").utf8).write(to: url) // rewritten, shorter
        #expect(tracker.refresh().inputTokens == 7)
    }

    @Test func aMissingFileIsEmptyNotAnError() {
        let tracker = UsageTracker(path: "/tmp/cn-does-not-exist-\(UUID().uuidString).jsonl")
        #expect(tracker.refresh().messageCount == 0)
    }

    @Test func aBigFileIsReadInChunksCorrectly() throws {
        var lines: [String] = []
        for i in 0..<3_000 { lines.append(assistant(id: "m\(i)", input: 1, output: 2, cacheRead: 3)) }
        let url = try makeFile(lines)
        let snap = UsageTracker(path: url.path).refresh()
        #expect(snap.messageCount == 3_000 && snap.inputTokens == 3_000 && snap.outputTokens == 6_000)
    }
}

@Suite struct UsageSummaryTests {
    private func snapshot(context: Int, window: Int?, cost: Double?, unpriced: Int = 0, messages: Int = 1) -> UsageSnapshot {
        UsageSnapshot(model: "m", contextTokens: context, contextWindow: window, costUSD: cost,
                      inputTokens: 0, outputTokens: 0, messageCount: messages, unpricedMessages: unpriced)
    }

    @Test func showsContextPercentAndCost() {
        #expect(snapshot(context: 380_000, window: 1_000_000, cost: 0.42).summary == "context 38% · $0.42")
    }

    @Test func percentIsRoundedAndNeverShowsZeroWhenThereIsContext() {
        #expect(snapshot(context: 4_000, window: 1_000_000, cost: 1).summary?.hasPrefix("context <1%") == true)
        #expect(snapshot(context: 12_600, window: 1_000_000, cost: 1).summary?.hasPrefix("context 1%") == true)
    }

    @Test func percentIsCappedAt100() {
        #expect(snapshot(context: 2_000_000, window: 1_000_000, cost: 1).summary?.hasPrefix("context 100%") == true)
    }

    @Test func costFormats() {
        #expect(snapshot(context: 1, window: 100, cost: 0.004).summary?.hasSuffix("<$0.01") == true)
        #expect(snapshot(context: 1, window: 100, cost: 12.345).summary?.hasSuffix("$12.35") == true)
        #expect(snapshot(context: 1, window: 100, cost: 1234.5).summary?.hasSuffix("$1,235") == true)
    }

    @Test func aPartialCostGetsAPlus() {
        #expect(snapshot(context: 1, window: 100, cost: 3.5, unpriced: 2).summary?.hasSuffix("$3.50+") == true)
    }

    @Test func withoutAWindowOnlyTheCostShows() {
        #expect(snapshot(context: 5_000, window: nil, cost: 0.10).summary == "$0.10")
    }

    @Test func withoutAnyPricedMessageOnlyTheContextShows() {
        #expect(snapshot(context: 100_000, window: 1_000_000, cost: nil).summary == "context 10%")
    }

    @Test func nothingToShowForAnEmptySession() {
        #expect(snapshot(context: 0, window: nil, cost: nil, messages: 0).summary == nil)
    }
}
