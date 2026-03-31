import Foundation

/// OpenAI / Codex model pricing (per-token rates)
/// Matches CodexBar pricing for gpt-5 / Codex default
/// Source: CodexBar/Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift
struct ModelPricing {
    let inputCostPerToken: Double
    let outputCostPerToken: Double
    let cacheReadInputCostPerToken: Double

    /// GPT-5 / Codex default pricing (per-token)
    /// Input: $1.25/1M tokens = 1.25e-6 per token
    /// Output: $10/1M tokens = 1e-5 per token
    /// Cache read: $0.125/1M tokens = 1.25e-7 per token
    static let codexDefault = ModelPricing(
        inputCostPerToken: 1.25e-6,
        outputCostPerToken: 1e-5,
        cacheReadInputCostPerToken: 1.25e-7
    )

    /// GPT-5-mini pricing
    static let gpt5Mini = ModelPricing(
        inputCostPerToken: 2.5e-7,
        outputCostPerToken: 2e-6,
        cacheReadInputCostPerToken: 2.5e-8
    )

    /// GPT-5-nano pricing
    static let gpt5Nano = ModelPricing(
        inputCostPerToken: 5e-8,
        outputCostPerToken: 4e-7,
        cacheReadInputCostPerToken: 5e-9
    )

    /// GPT-5-pro pricing
    static let gpt5Pro = ModelPricing(
        inputCostPerToken: 1.5e-5,
        outputCostPerToken: 1.2e-4,
        cacheReadInputCostPerToken: 1.5e-6
    )

    /// Normalize model name to pricing key
    static func normalizeModel(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("openai/") {
            trimmed = String(trimmed.dropFirst("openai/".count))
        }

        if let datedSuffix = trimmed.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            let base = String(trimmed[..<datedSuffix.lowerBound])
            let knownModels = ["gpt-5", "gpt-5-mini", "gpt-5-nano", "gpt-5-pro",
                               "gpt-5.1", "gpt-5.2", "gpt-5.3", "gpt-5.4"]
            if knownModels.contains(where: { base.hasPrefix($0) }) {
                return base
            }
        }

        return trimmed
    }
}

/// Computes USD cost from token usage using CodexBar-compatible formula
struct CostCalculator {
    let pricing: ModelPricing

    init(pricing: ModelPricing = .codexDefault) {
        self.pricing = pricing
    }

    /// Calculate cost for a given token usage
    /// Formula matches CodexBar:
    /// cost = nonCached * inputCost + cached * cacheReadCost + output * outputCost
    func cost(for usage: AccountTokenUsage) -> Double {
        let input = max(0, usage.inputTokens)
        let cached = min(max(0, usage.cachedInputTokens), input)
        let nonCached = input - cached
        let output = max(0, usage.outputTokens)

        return Double(nonCached) * pricing.inputCostPerToken
             + Double(cached) * pricing.cacheReadInputCostPerToken
             + Double(output) * pricing.outputCostPerToken
    }

    /// Format cost as USD string
    static func format(_ cost: Double) -> String {
        if cost < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", cost)
    }
}
