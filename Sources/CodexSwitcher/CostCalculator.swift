import Foundation

/// OpenAI / Codex model pricing (per-token rates)
/// Matches CodexBar pricing for gpt-5 family
/// Source: CodexBar/Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift
struct ModelPricing {
    let inputCostPerToken: Double
    let outputCostPerToken: Double
    let cacheReadInputCostPerToken: Double?

    /// GPT-5 / Codex default pricing (per-token)
    /// Input: $1.25/1M tokens = 1.25e-6 per token
    /// Output: $10/1M tokens = 1e-5 per token
    /// Cache read: $0.125/1M tokens = 1.25e-7 per token
    static let codexDefault = ModelPricing(
        inputCostPerToken: 1.25e-6,
        outputCostPerToken: 1e-5,
        cacheReadInputCostPerToken: 1.25e-7
    )

    /// All known model pricing from CodexBar
    static let allPricing: [String: ModelPricing] = [
        // GPT-5 family
        "gpt-5": ModelPricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7),
        "gpt-5-codex": ModelPricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7),
        "gpt-5-mini": ModelPricing(inputCostPerToken: 2.5e-7, outputCostPerToken: 2e-6, cacheReadInputCostPerToken: 2.5e-8),
        "gpt-5-nano": ModelPricing(inputCostPerToken: 5e-8, outputCostPerToken: 4e-7, cacheReadInputCostPerToken: 5e-9),
        "gpt-5-pro": ModelPricing(inputCostPerToken: 1.5e-5, outputCostPerToken: 1.2e-4, cacheReadInputCostPerToken: nil),

        // GPT-5.1 family
        "gpt-5.1": ModelPricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7),
        "gpt-5.1-codex": ModelPricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7),
        "gpt-5.1-codex-max": ModelPricing(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadInputCostPerToken: 1.25e-7),
        "gpt-5.1-codex-mini": ModelPricing(inputCostPerToken: 2.5e-7, outputCostPerToken: 2e-6, cacheReadInputCostPerToken: 2.5e-8),

        // GPT-5.2 family
        "gpt-5.2": ModelPricing(inputCostPerToken: 1.75e-6, outputCostPerToken: 1.4e-5, cacheReadInputCostPerToken: 1.75e-7),
        "gpt-5.2-codex": ModelPricing(inputCostPerToken: 1.75e-6, outputCostPerToken: 1.4e-5, cacheReadInputCostPerToken: 1.75e-7),
        "gpt-5.2-pro": ModelPricing(inputCostPerToken: 2.1e-5, outputCostPerToken: 1.68e-4, cacheReadInputCostPerToken: nil),

        // GPT-5.3 family
        "gpt-5.3-codex": ModelPricing(inputCostPerToken: 1.75e-6, outputCostPerToken: 1.4e-5, cacheReadInputCostPerToken: 1.75e-7),
        "gpt-5.3-codex-spark": ModelPricing(inputCostPerToken: 0, outputCostPerToken: 0, cacheReadInputCostPerToken: 0),

        // GPT-5.4 family
        "gpt-5.4": ModelPricing(inputCostPerToken: 2.5e-6, outputCostPerToken: 1.5e-5, cacheReadInputCostPerToken: 2.5e-7),
        "gpt-5.4-mini": ModelPricing(inputCostPerToken: 7.5e-7, outputCostPerToken: 4.5e-6, cacheReadInputCostPerToken: 7.5e-8),
        "gpt-5.4-nano": ModelPricing(inputCostPerToken: 2e-7, outputCostPerToken: 1.25e-6, cacheReadInputCostPerToken: 2e-8),
        "gpt-5.4-pro": ModelPricing(inputCostPerToken: 3e-5, outputCostPerToken: 1.8e-4, cacheReadInputCostPerToken: nil),
    ]

    /// Get pricing for a model name (returns default if unknown)
    static func pricing(for model: String) -> ModelPricing {
        let normalized = normalizeModel(model)
        return allPricing[normalized] ?? .codexDefault
    }

    /// Normalize model name to pricing key
    static func normalizeModel(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("openai/") {
            trimmed = String(trimmed.dropFirst("openai/".count))
        }

        // Strip date suffix: gpt-5-2025-01-15 -> gpt-5
        if let datedSuffix = trimmed.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            let base = String(trimmed[..<datedSuffix.lowerBound])
            if allPricing[base] != nil {
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
        var totalCost: Double = 0

        // Calculate aggregate cost if we have model breakdown
        if !usage.modelUsage.isEmpty {
            for (model, modelUsage) in usage.modelUsage {
                let modelPricing = ModelPricing.pricing(for: model)
                totalCost += costForModelUsage(modelUsage, pricing: modelPricing)
            }
        } else {
            // Fallback to aggregate totals
            totalCost = costForModelUsage(
                ModelTokenUsage(
                    inputTokens: usage.inputTokens,
                    cachedInputTokens: usage.cachedInputTokens,
                    outputTokens: usage.outputTokens,
                    sessionCount: usage.sessionCount
                ),
                pricing: pricing
            )
        }

        return totalCost
    }

    private func costForModelUsage(_ usage: ModelTokenUsage, pricing: ModelPricing) -> Double {
        let input = max(0, usage.inputTokens)
        let cached = min(max(0, usage.cachedInputTokens), input)
        let nonCached = input - cached
        let output = max(0, usage.outputTokens)

        let cacheRate = pricing.cacheReadInputCostPerToken ?? pricing.inputCostPerToken

        return Double(nonCached) * pricing.inputCostPerToken
             + Double(cached) * cacheRate
             + Double(output) * pricing.outputCostPerToken
    }

    /// Format cost as USD string
    static func format(_ cost: Double) -> String {
        if cost < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", cost)
    }
}
