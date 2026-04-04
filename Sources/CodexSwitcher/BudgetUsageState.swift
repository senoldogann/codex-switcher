import Foundation

struct BudgetUsageState: Equatable, Sendable {
    let spent: Double
    let limit: Double
    let isEnabled: Bool
    let isExceeded: Bool
    let label: String

    static func make(spent: Double, limit: Double) -> BudgetUsageState {
        let safeSpent = max(0, spent)
        let safeLimit = max(0, limit)
        let isEnabled = safeLimit > 0

        return BudgetUsageState(
            spent: safeSpent,
            limit: safeLimit,
            isEnabled: isEnabled,
            isExceeded: isEnabled && safeSpent >= safeLimit,
            label: isEnabled
                ? "$\(String(format: "%.0f", safeSpent))/$\(String(format: "%.0f", safeLimit))"
                : L("Bütçe", "Budget")
        )
    }
}
