import Testing
@testable import CodexSwitcher

struct BudgetUsageStateTests {
    @Test
    func marksBudgetAsExceededWhenSpentReachesLimit() {
        let state = BudgetUsageState.make(spent: 125, limit: 100)

        #expect(state.isEnabled == true)
        #expect(state.isExceeded == true)
        #expect(state.label == "$125/$100")
    }

    @Test
    func keepsBudgetDisabledWhenLimitIsZero() {
        let state = BudgetUsageState.make(spent: 80, limit: 0)

        #expect(state.isEnabled == false)
        #expect(state.isExceeded == false)
        #expect(state.label == L("Bütçe", "Budget"))
    }
}
