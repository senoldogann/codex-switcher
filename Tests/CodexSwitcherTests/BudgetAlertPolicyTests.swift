import Foundation
import Testing
@testable import CodexSwitcher

struct BudgetAlertPolicyTests {
    @Test
    func returnsAlertWhenBudgetIsExceeded() {
        let now = Date(timeIntervalSince1970: 1_700_020_000)
        let result = BudgetAlertPolicy.shouldAlert(
            totalCost: 120,
            budgetLimit: 100,
            lastAlertDate: nil,
            now: now
        )

        #expect(result == true)
    }

    @Test
    func suppressesRepeatAlertOnSameDay() {
        let now = Date(timeIntervalSince1970: 1_700_020_000)
        let result = BudgetAlertPolicy.shouldAlert(
            totalCost: 120,
            budgetLimit: 100,
            lastAlertDate: now.addingTimeInterval(-3600),
            now: now
        )

        #expect(result == false)
    }
}
