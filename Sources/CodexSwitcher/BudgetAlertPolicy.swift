import Foundation

enum BudgetAlertPolicy {
    static func shouldAlert(
        totalCost: Double,
        budgetLimit: Double,
        lastAlertDate: Date?,
        now: Date
    ) -> Bool {
        guard budgetLimit > 0, totalCost >= budgetLimit else { return false }
        let today = Calendar.current.startOfDay(for: now)
        if let lastAlertDate, Calendar.current.startOfDay(for: lastAlertDate) == today {
            return false
        }
        return true
    }
}
