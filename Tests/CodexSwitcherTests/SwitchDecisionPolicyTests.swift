import Foundation
import Testing
@testable import CodexSwitcher

struct SwitchDecisionPolicyTests {
    @Test
    func shouldLeaveCurrentProfileWhenWeeklyRemainingHitsThreshold() {
        let policy = SwitchDecisionPolicy()
        let rateLimit = RateLimitInfo(
            planType: "plus",
            allowed: true,
            limitReached: false,
            weeklyUsedPercent: 95,
            weeklyResetAt: nil,
            fiveHourRemainingPercent: 40,
            fiveHourResetAt: nil
        )

        #expect(policy.shouldLeaveCurrentProfile(rateLimit) == true)
    }

    @Test
    func shouldLeaveCurrentProfileWhenFiveHourRemainingHitsThreshold() {
        let policy = SwitchDecisionPolicy()
        let rateLimit = RateLimitInfo(
            planType: "plus",
            allowed: true,
            limitReached: false,
            weeklyUsedPercent: 60,
            weeklyResetAt: nil,
            fiveHourRemainingPercent: 7,
            fiveHourResetAt: nil
        )

        #expect(policy.shouldLeaveCurrentProfile(rateLimit) == true)
    }

    @Test
    func candidateEligibilityRejectsNearExhaustedProfilesAndKeepsUnknownProfiles() {
        let policy = SwitchDecisionPolicy()
        let exhausted = RateLimitInfo(
            planType: "plus",
            allowed: true,
            limitReached: false,
            weeklyUsedPercent: 96,
            weeklyResetAt: nil,
            fiveHourRemainingPercent: 6,
            fiveHourResetAt: nil
        )

        #expect(policy.isEligibleCandidate(exhausted) == false)
        #expect(policy.isEligibleCandidate(nil) == true)
    }

    @Test
    func nextAutomaticCandidateSkipsProfilesNearThresholdAndPrefersLowestWeeklyUsage() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let active = Profile(alias: "Active", email: "active@example.com", accountId: "acct-active", addedAt: now)
        let safe = Profile(alias: "Safe", email: "safe@example.com", accountId: "acct-safe", addedAt: now)
        let nearFiveHour = Profile(alias: "Near5h", email: "near@example.com", accountId: "acct-near", addedAt: now)
        let unknown = Profile(alias: "Unknown", email: "unknown@example.com", accountId: "acct-unknown", addedAt: now)
        let policy = SwitchDecisionPolicy()

        let candidate = policy.nextAutomaticCandidate(
            profiles: [active, safe, nearFiveHour, unknown],
            activeProfileId: active.id,
            rateLimits: [
                safe.id: RateLimitInfo(
                    planType: "plus",
                    allowed: true,
                    limitReached: false,
                    weeklyUsedPercent: 12,
                    weeklyResetAt: nil,
                    fiveHourRemainingPercent: 60,
                    fiveHourResetAt: nil
                ),
                nearFiveHour.id: RateLimitInfo(
                    planType: "plus",
                    allowed: true,
                    limitReached: false,
                    weeklyUsedPercent: 10,
                    weeklyResetAt: nil,
                    fiveHourRemainingPercent: 7,
                    fiveHourResetAt: nil
                )
            ]
        )

        #expect(candidate?.id == unknown.id)
    }

    @Test
    func automaticReasonReflectsFiveHourAndWeeklyPressure() {
        let policy = SwitchDecisionPolicy()
        let fiveHour = RateLimitInfo(
            planType: "plus",
            allowed: true,
            limitReached: false,
            weeklyUsedPercent: 70,
            weeklyResetAt: nil,
            fiveHourRemainingPercent: 5,
            fiveHourResetAt: nil
        )
        let weekly = RateLimitInfo(
            planType: "plus",
            allowed: true,
            limitReached: false,
            weeklyUsedPercent: 97,
            weeklyResetAt: nil,
            fiveHourRemainingPercent: 50,
            fiveHourResetAt: nil
        )

        #expect(policy.automaticReasonKind(for: fiveHour) == .fiveHourPressure)
        #expect(policy.automaticReasonKind(for: weekly) == .weeklyPressure)
    }
}
