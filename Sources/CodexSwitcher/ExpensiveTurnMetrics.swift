import Foundation

struct ExpensiveTurnMetrics {
    let turns: [ExpensiveTurn]

    private var maxCost: Double {
        turns.map(\.cost).max() ?? 0
    }

    func costFraction(for turn: ExpensiveTurn) -> Double {
        guard maxCost > 0 else { return 0 }
        return min(max(turn.cost / maxCost, 0), 1)
    }

    static func formatCost(_ cost: Double) -> String {
        guard cost > 0 else { return "$0.00" }
        if cost >= 100 { return String(format: "$%.0f", cost) }
        if cost >= 1 { return String(format: "$%.2f", cost) }
        if cost >= 0.01 { return String(format: "$%.3f", cost) }
        return String(format: "$%.4f", cost)
    }

    static func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return String(format: "%.1fK", Double(tokens) / 1_000) }
        return "\(tokens)"
    }
}
