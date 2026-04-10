import Foundation
import Testing
@testable import CodexSwitcher

struct SwitchReadinessEvaluatorTests {
    @Test
    func activeProfileIsNeverPreferred() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let active = Profile(alias: "Active", email: "active@example.com", accountId: "acct-active", addedAt: now)
        let safe = Profile(alias: "Safe", email: "safe@example.com", accountId: "acct-safe", addedAt: now)
        let evaluator = SwitchReadinessEvaluator(policy: SwitchDecisionPolicy())

        let evaluation = evaluator.evaluate(
            profiles: [active, safe],
            activeProfileId: active.id,
            rateLimits: [
                active.id: RateLimitInfo(
                    planType: "plus",
                    allowed: true,
                    limitReached: false,
                    weeklyUsedPercent: 20,
                    weeklyResetAt: nil,
                    fiveHourRemainingPercent: 60,
                    fiveHourResetAt: nil
                ),
                safe.id: RateLimitInfo(
                    planType: "plus",
                    allowed: true,
                    limitReached: false,
                    weeklyUsedPercent: 10,
                    weeklyResetAt: nil,
                    fiveHourRemainingPercent: 80,
                    fiveHourResetAt: nil
                )
            ],
            staleProfileIds: []
        )

        #expect(evaluation.preferredCandidateId == safe.id)
        #expect(evaluation.candidates.first?.profileId == safe.id)
    }

    @Test
    func staleAndMissingRateLimitBecomeWarnings() {
        let now = Date(timeIntervalSince1970: 1_760_000_001)
        let stale = Profile(alias: "Stale", email: "stale@example.com", accountId: "acct-stale", addedAt: now)
        let evaluator = SwitchReadinessEvaluator(policy: SwitchDecisionPolicy())

        let evaluation = evaluator.evaluate(
            profiles: [stale],
            activeProfileId: nil,
            rateLimits: [:],
            staleProfileIds: [stale.id]
        )

        #expect(evaluation.candidates.first?.status == .warning)
        #expect(evaluation.candidates.first?.reasons.contains(.staleAuth) == true)
        #expect(evaluation.candidates.first?.reasons.contains(.missingRateLimit) == true)
    }

    @Test
    func exhaustedTargetsAreBlocked() {
        let now = Date(timeIntervalSince1970: 1_760_000_002)
        let blocked = Profile(alias: "Blocked", email: "blocked@example.com", accountId: "acct-blocked", addedAt: now)
        let evaluator = SwitchReadinessEvaluator(policy: SwitchDecisionPolicy())

        let evaluation = evaluator.evaluate(
            profiles: [blocked],
            activeProfileId: nil,
            rateLimits: [
                blocked.id: RateLimitInfo(
                    planType: "plus",
                    allowed: true,
                    limitReached: true,
                    weeklyUsedPercent: 100,
                    weeklyResetAt: nil,
                    fiveHourRemainingPercent: 0,
                    fiveHourResetAt: nil
                )
            ],
            staleProfileIds: []
        )

        #expect(evaluation.candidates.first?.status == .blocked)
        #expect(evaluation.preferredCandidateId == nil)
    }
}
