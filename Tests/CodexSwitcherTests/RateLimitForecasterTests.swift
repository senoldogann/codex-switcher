import Foundation
import Testing
@testable import CodexSwitcher

struct RateLimitForecasterTests {

    // MARK: - Weekly-zero gate

    @Test("forecast returns exhausted when weekly remaining is 0, regardless of 5-hour remaining")
    func exhaustedWhenWeeklyIsZeroAndFiveHourIsFull() {
        let rl = RateLimitInfo(
            planType: "plus",
            allowed: true,
            limitReached: false,
            weeklyUsedPercent: 100,   // weekly remaining = 0
            weeklyResetAt: nil,
            fiveHourRemainingPercent: 100,  // 5h looks full — should be ignored
            fiveHourResetAt: nil
        )
        let forecast = RateLimitForecaster.forecast(
            profileId: UUID(),
            rateLimit: rl,
            tokenUsage: nil,
            sessionHistory: []
        )
        #expect(forecast.riskLevel == .exhausted)
    }

    @Test("forecast returns exhausted when weekly remaining is 0 and 5-hour remaining is also 0")
    func exhaustedWhenBothWindowsAreEmpty() {
        let rl = RateLimitInfo(
            planType: "plus",
            allowed: true,
            limitReached: false,
            weeklyUsedPercent: 100,
            weeklyResetAt: nil,
            fiveHourRemainingPercent: 0,
            fiveHourResetAt: nil
        )
        let forecast = RateLimitForecaster.forecast(
            profileId: UUID(),
            rateLimit: rl,
            tokenUsage: nil,
            sessionHistory: []
        )
        #expect(forecast.riskLevel == .exhausted)
    }

    @Test("forecast returns safe when weekly has capacity and 5-hour is full")
    func safeWhenWeeklyHasCapacityAndFiveHourIsFull() {
        let rl = RateLimitInfo(
            planType: "plus",
            allowed: true,
            limitReached: false,
            weeklyUsedPercent: 40,   // 60% remaining
            weeklyResetAt: nil,
            fiveHourRemainingPercent: 100,
            fiveHourResetAt: nil
        )
        let forecast = RateLimitForecaster.forecast(
            profileId: UUID(),
            rateLimit: rl,
            tokenUsage: nil,
            sessionHistory: []
        )
        #expect(forecast.riskLevel == .safe)
    }

    @Test("forecast uses 5-hour remaining for risk level when weekly has capacity")
    func criticalWhenFiveHourIsLowButWeeklyHasCapacity() {
        let rl = RateLimitInfo(
            planType: "plus",
            allowed: true,
            limitReached: false,
            weeklyUsedPercent: 40,   // 60% weekly remaining — not exhausted
            weeklyResetAt: nil,
            fiveHourRemainingPercent: 5,   // 5h is critical
            fiveHourResetAt: nil
        )
        let forecast = RateLimitForecaster.forecast(
            profileId: UUID(),
            rateLimit: rl,
            tokenUsage: nil,
            sessionHistory: []
        )
        #expect(forecast.riskLevel == .critical)
    }

    @Test("forecast returns exhausted when limitReached is true")
    func exhaustedWhenLimitReached() {
        let rl = RateLimitInfo(
            planType: "plus",
            allowed: false,
            limitReached: true,
            weeklyUsedPercent: nil,
            weeklyResetAt: nil,
            fiveHourRemainingPercent: nil,
            fiveHourResetAt: nil
        )
        let forecast = RateLimitForecaster.forecast(
            profileId: UUID(),
            rateLimit: rl,
            tokenUsage: nil,
            sessionHistory: []
        )
        #expect(forecast.riskLevel == .exhausted)
    }

    @Test("forecast returns safe when no rate limit data is available")
    func safeWhenNoRateLimitData() {
        let forecast = RateLimitForecaster.forecast(
            profileId: UUID(),
            rateLimit: nil,
            tokenUsage: nil,
            sessionHistory: []
        )
        #expect(forecast.riskLevel == .safe)
    }
}
