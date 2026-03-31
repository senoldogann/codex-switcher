import Foundation

/// OpenAI model pricing (per 1M tokens, USD)
/// Source: https://openai.com/api/pricing/
struct ModelPricing {
    let inputPerM: Double
    let cachedInputPerM: Double
    let outputPerM: Double

    /// Default pricing for Codex (GPT-4.1 / GPT-4o family)
    static let codexDefault = ModelPricing(
        inputPerM: 2.0,
        cachedInputPerM: 0.5,
        outputPerM: 8.0
    )

    /// Pricing for Codex Pro / Plus plans (GPT-4o)
    static let codexPro = ModelPricing(
        inputPerM: 2.5,
        cachedInputPerM: 1.25,
        outputPerM: 10.0
    )

    /// GPT-4o mini pricing
    static let gpt4oMini = ModelPricing(
        inputPerM: 0.15,
        cachedInputPerM: 0.075,
        outputPerM: 0.6
    )

    /// o1 pricing
    static let o1 = ModelPricing(
        inputPerM: 15.0,
        cachedInputPerM: 7.5,
        outputPerM: 60.0
    )

    /// o3-mini pricing
    static let o3Mini = ModelPricing(
        inputPerM: 1.1,
        cachedInputPerM: 0.55,
        outputPerM: 4.4
    )
}

/// Computes USD cost from token usage
struct CostCalculator {
    let pricing: ModelPricing

    init(pricing: ModelPricing = .codexDefault) {
        self.pricing = pricing
    }

    /// Calculate cost for a given token usage
    func cost(for usage: AccountTokenUsage) -> Double {
        let inputCost = Double(usage.inputTokens) / 1_000_000 * pricing.inputPerM
        let cachedCost = Double(usage.cachedInputTokens) / 1_000_000 * pricing.cachedInputPerM
        let outputCost = Double(usage.outputTokens) / 1_000_000 * pricing.outputPerM
        return inputCost + cachedCost + outputCost
    }

    /// Format cost as USD string
    static func format(_ cost: Double) -> String {
        if cost < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", cost)
    }
}
