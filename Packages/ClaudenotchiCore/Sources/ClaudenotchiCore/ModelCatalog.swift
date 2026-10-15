import Foundation

/// Tokens of one request, split the way they are billed.
public struct TokenUsage: Equatable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite5m: Int
    public var cacheWrite1h: Int

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
    }

    /// Everything the model read for this request: the size of the context.
    public var promptTokens: Int { input + cacheRead + cacheWrite5m + cacheWrite1h }
}

/// List prices in US dollars per million tokens. Cache writes are 1.25x (5 minutes) and 2x (1 hour) the
/// input price. These are standard API rates: batch, fast mode and priority tiers are not modelled, so
/// the result is an estimate.
public struct ModelPricing: Equatable, Sendable {
    public var inputPerMTok: Double
    public var outputPerMTok: Double
    public var cacheReadPerMTok: Double

    public var cacheWrite5mPerMTok: Double { inputPerMTok * 1.25 }
    public var cacheWrite1hPerMTok: Double { inputPerMTok * 2 }

    /// Higher rates for requests whose prompt exceeds `threshold` tokens (Claude Haiku 5.5).
    struct LongPrompt: Equatable, Sendable {
        var threshold: Int
        var inputPerMTok: Double
        var outputPerMTok: Double
        var cacheReadPerMTok: Double
    }

    var longPrompt: LongPrompt?

    public func cost(for tokens: TokenUsage) -> Double {
        var rates = self
        if let tier = longPrompt, tokens.promptTokens > tier.threshold {
            rates = ModelPricing(inputPerMTok: tier.inputPerMTok, outputPerMTok: tier.outputPerMTok, cacheReadPerMTok: tier.cacheReadPerMTok)
        }
        let dollars = Double(tokens.input) * rates.inputPerMTok
            + Double(tokens.output) * rates.outputPerMTok
            + Double(tokens.cacheRead) * rates.cacheReadPerMTok
            + Double(tokens.cacheWrite5m) * rates.cacheWrite5mPerMTok
            + Double(tokens.cacheWrite1h) * rates.cacheWrite1hPerMTok
        return dollars / 1_000_000
    }
}

/// Prices and context windows of the models Claude Code can run. Unknown models are reported as unknown
/// (nil), never guessed.
public enum ModelCatalog {
    private static func price(_ input: Double, _ output: Double, read: Double, long: ModelPricing.LongPrompt? = nil) -> ModelPricing {
        ModelPricing(inputPerMTok: input, outputPerMTok: output, cacheReadPerMTok: read, longPrompt: long)
    }

    // Source: the Claude API model table (cached 2026-10-06). Cache reads are 0.1x input unless stated;
    // Claude Haiku 5.5's cache-read rate is assumed to follow that 0.1x rule (the table does not list it).
    private static let prices: [String: ModelPricing] = [
        "claude-fable-5-1": price(10, 50, read: 0.25),
        "claude-mythos-5-1": price(10, 50, read: 0.25),
        "claude-fable-5": price(10, 50, read: 1),
        "claude-mythos-5": price(10, 50, read: 1),
        "claude-opus-5-5": price(4, 20, read: 0.2),
        "claude-opus-5": price(5, 25, read: 0.5),
        "claude-opus-4-8": price(5, 25, read: 0.5),
        "claude-opus-4-7": price(5, 25, read: 0.5),
        "claude-opus-4-6": price(5, 25, read: 0.5),
        "claude-sonnet-5-5": price(2, 10, read: 0.2),
        "claude-sonnet-5": price(2, 10, read: 0.2),
        "claude-sonnet-4-6": price(3, 15, read: 0.3),
        "claude-haiku-5-5": price(0.10, 0.50, read: 0.01, long: .init(threshold: 100_000, inputPerMTok: 0.50, outputPerMTok: 2.50, cacheReadPerMTok: 0.05)),
        "claude-haiku-4-5": price(1, 5, read: 0.1),
    ]

    private static let windows: [String: Int] = {
        var result = prices.mapValues { _ in 1_000_000 }
        result["claude-haiku-4-5"] = 200_000
        return result
    }()

    /// `claude-opus-5-5[1m]` -> `claude-opus-5-5`; `Claude-Opus-4-6-20251101` -> `claude-opus-4-6`.
    public static func canonical(_ model: String) -> String {
        var id = model.lowercased()
        if let bracket = id.firstIndex(of: "[") { id = String(id[..<bracket]) }
        if let at = id.firstIndex(of: "@") { id = String(id[..<at]) }
        if let match = id.range(of: #"-\d{8}$"#, options: .regularExpression) { id.removeSubrange(match) }
        return id
    }

    public static func pricing(for model: String) -> ModelPricing? { prices[canonical(model)] }

    public static func contextWindow(for model: String) -> Int? { windows[canonical(model)] }
}
