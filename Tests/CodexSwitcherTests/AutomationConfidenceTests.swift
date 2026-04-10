import Foundation
import Testing
@testable import CodexSwitcher

struct AutomationConfidenceTests {
    @Test
    func summaryBecomesCriticalWhenPendingSwitchIsStuck() {
        let now = Date(timeIntervalSince1970: 1_700_010_000)
        let profileId = UUID()
        let summary = AutomationConfidenceCalculator.buildSummary(
            profiles: [
                Profile(alias: "Account 1", email: "one@example.com", accountId: "acc-1", addedAt: now)
            ],
            staleProfileIds: [],
            rateLimitHealth: [:],
            reliability: SwitchReliabilitySnapshot(),
            pendingSwitchRequest: PendingSwitchRequest(
                targetProfileId: profileId,
                targetProfileName: "Account 2",
                reason: "Limit reached",
                queuedAt: now.addingTimeInterval(-95)
            ),
            switchTimeline: [],
            now: now
        )

        #expect(summary.status == .critical)
        #expect(summary.stuckPendingSwitch == true)
        #expect(summary.highlight.contains("95"))
    }

    @Test
    func summaryFlagsAttentionWhenFallbacksOutnumberSeamlessSwitches() {
        let now = Date(timeIntervalSince1970: 1_700_010_100)
        let summary = AutomationConfidenceCalculator.buildSummary(
            profiles: [
                Profile(alias: "Account 1", email: "one@example.com", accountId: "acc-1", addedAt: now)
            ],
            staleProfileIds: [],
            rateLimitHealth: [:],
            reliability: SwitchReliabilitySnapshot(
                pendingSwitchCount: 2,
                completedDeferredSwitchCount: 2,
                seamlessSuccessCount: 1,
                inconclusiveCount: 0,
                fallbackRestartCount: 3,
                blockedDecisionCount: 0,
                haltedDecisionCount: 0
            ),
            pendingSwitchRequest: nil,
            switchTimeline: [],
            now: now
        )

        #expect(summary.status == .warning)
        #expect(summary.highlight.contains("fallback"))
    }

    @Test
    func summaryIsHealthyWhenNoStaleProfilesAndSeamlessSwitchesSucceed() {
        let now = Date(timeIntervalSince1970: 1_700_010_200)
        let summary = AutomationConfidenceCalculator.buildSummary(
            profiles: [
                Profile(alias: "Account 1", email: "one@example.com", accountId: "acc-1", addedAt: now)
            ],
            staleProfileIds: [],
            rateLimitHealth: [:],
            reliability: SwitchReliabilitySnapshot(
                pendingSwitchCount: 1,
                completedDeferredSwitchCount: 1,
                seamlessSuccessCount: 4,
                inconclusiveCount: 1,
                fallbackRestartCount: 0,
                blockedDecisionCount: 0,
                haltedDecisionCount: 0
            ),
            pendingSwitchRequest: nil,
            switchTimeline: [
                SwitchTimelineEvent(
                    id: UUID(),
                    timestamp: now.addingTimeInterval(-30),
                    stage: .seamlessSuccess,
                    targetProfileName: "Account 1",
                    reason: "Limit reached",
                    detail: "Verified",
                    waitDurationSeconds: 8,
                    verificationDurationSeconds: 2
                )
            ],
            now: now
        )

        #expect(summary.status == .healthy)
        #expect(summary.highlight.contains("healthy"))
        #expect(summary.lastVerifiedSwitchAt == now.addingTimeInterval(-30))
    }

    @Test
    func summaryWarnsWhenAutomationRecentlyHalted() {
        let now = Date(timeIntervalSince1970: 1_700_010_250)
        let summary = AutomationConfidenceCalculator.buildSummary(
            profiles: [
                Profile(alias: "Account 1", email: "one@example.com", accountId: "acc-1", addedAt: now)
            ],
            staleProfileIds: [],
            rateLimitHealth: [:],
            reliability: SwitchReliabilitySnapshot(
                pendingSwitchCount: 0,
                completedDeferredSwitchCount: 0,
                seamlessSuccessCount: 1,
                inconclusiveCount: 0,
                fallbackRestartCount: 0,
                blockedDecisionCount: 0,
                haltedDecisionCount: 1
            ),
            pendingSwitchRequest: nil,
            switchTimeline: [],
            now: now
        )

        #expect(summary.status == .warning)
        #expect(summary.highlight.contains("safe target"))
    }

    @Test
    func accountReliabilityRanksStaleProfilesAboveHealthyOnes() {
        let now = Date(timeIntervalSince1970: 1_700_010_300)
        let staleId = UUID()
        let healthyId = UUID()
        let summaries = AutomationConfidenceCalculator.buildAccountSummaries(
            profiles: [
                Profile(id: staleId, alias: "Account 1", email: "one@example.com", accountId: "acc-1", addedAt: now),
                Profile(id: healthyId, alias: "Account 2", email: "two@example.com", accountId: "acc-2", addedAt: now)
            ],
            staleProfileIds: [staleId],
            rateLimitHealth: [
                staleId: RateLimitHealthStatus(
                    lastCheckedAt: now,
                    lastSuccessfulFetchAt: nil,
                    lastFailedFetchAt: now,
                    lastHTTPStatusCode: 401,
                    staleReason: .unauthorized,
                    failureSummary: "401 unauthorized"
                ),
                healthyId: RateLimitHealthStatus(
                    lastCheckedAt: now,
                    lastSuccessfulFetchAt: now,
                    lastFailedFetchAt: nil,
                    lastHTTPStatusCode: 200,
                    staleReason: nil,
                    failureSummary: nil
                )
            ],
            forecasts: [:],
            costs: [:],
            now: now
        )

        #expect(summaries.count == 2)
        #expect(summaries.first?.profileId == staleId)
        #expect(summaries.first?.status == .critical)
        #expect(summaries.first?.detail.contains("401") == true)
        #expect(summaries.last?.status == .healthy)
    }
}
