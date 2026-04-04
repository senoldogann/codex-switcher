import Foundation
import Testing
@testable import CodexSwitcher

struct ReconciliationModelsTests {
    @Test
    func statusReasonAndConfidenceUseStableRawValues() throws {
        #expect(ReconciliationStatus.explained.rawValue == "explained")
        #expect(ReconciliationStatus.weakAttribution.rawValue == "weakAttribution")
        #expect(ReconciliationStatus.unexplained.rawValue == "unexplained")
        #expect(ReconciliationStatus.ignored.rawValue == "ignored")

        #expect(ReconciliationReasonCode.matchedActivity.rawValue == "matched_activity")
        #expect(ReconciliationReasonCode.lowLocalUsage.rawValue == "low_local_usage")
        #expect(ReconciliationReasonCode.idleDrain.rawValue == "idle_drain")
        #expect(ReconciliationReasonCode.missingProviderSample.rawValue == "missing_provider_sample")
        #expect(ReconciliationReasonCode.switchBoundaryOverlap.rawValue == "switch_boundary_overlap")
        #expect(ReconciliationReasonCode.belowNoiseFloor.rawValue == "below_noise_floor")
        #expect(ReconciliationReasonCode.sampleResetOrCounterJump.rawValue == "sample_reset_or_counter_jump")

        #expect(ReconciliationConfidence.high.rawValue == "high")
        #expect(ReconciliationConfidence.medium.rawValue == "medium")
        #expect(ReconciliationConfidence.low.rawValue == "low")

        let encoded = try JSONEncoder().encode(ReconciliationReasonCode.switchBoundaryOverlap)
        let decoded = try JSONDecoder().decode(ReconciliationReasonCode.self, from: encoded)
        #expect(decoded == .switchBoundaryOverlap)
    }

    @Test
    func summaryAggregatesCountsTotalsAndLatestWindow() {
        let profileId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let entries = [
            ReconciliationEntry(
                profileId: profileId,
                profileName: "Alpha",
                windowStart: Date(timeIntervalSince1970: 100),
                windowEnd: Date(timeIntervalSince1970: 200),
                providerWeeklyDeltaPercent: 8,
                providerFiveHourDeltaPercent: 0,
                localTokens: 12_000,
                matchedSessionIds: ["s1", "s2"],
                status: .explained,
                reasonCode: .matchedActivity,
                confidence: .high
            ),
            ReconciliationEntry(
                profileId: profileId,
                profileName: "Alpha",
                windowStart: Date(timeIntervalSince1970: 200),
                windowEnd: Date(timeIntervalSince1970: 300),
                providerWeeklyDeltaPercent: 4,
                providerFiveHourDeltaPercent: 2,
                localTokens: 120,
                matchedSessionIds: ["s3"],
                status: .weakAttribution,
                reasonCode: .lowLocalUsage,
                confidence: .medium
            ),
            ReconciliationEntry(
                profileId: profileId,
                profileName: "Alpha",
                windowStart: Date(timeIntervalSince1970: 300),
                windowEnd: Date(timeIntervalSince1970: 500),
                providerWeeklyDeltaPercent: 3,
                providerFiveHourDeltaPercent: 5,
                localTokens: 0,
                matchedSessionIds: [],
                status: .unexplained,
                reasonCode: .idleDrain,
                confidence: .low
            ),
            ReconciliationEntry(
                profileId: profileId,
                profileName: "Alpha",
                windowStart: Date(timeIntervalSince1970: 500),
                windowEnd: Date(timeIntervalSince1970: 700),
                providerWeeklyDeltaPercent: nil,
                providerFiveHourDeltaPercent: nil,
                localTokens: 0,
                matchedSessionIds: [],
                status: .ignored,
                reasonCode: .missingProviderSample,
                confidence: .low
            )
        ]

        let summary = ReconciliationSummary(entries: entries)

        #expect(summary.explainedCount == 1)
        #expect(summary.weakAttributionCount == 1)
        #expect(summary.unexplainedCount == 1)
        #expect(summary.ignoredCount == 1)
        #expect(summary.idleDrainCount == 1)
        #expect(summary.totalWindowCount == 4)
        #expect(summary.totalProviderWeeklyDeltaPercent == 15)
        #expect(summary.totalProviderFiveHourDeltaPercent == 7)
        #expect(summary.totalLocalTokens == 12_120)
        #expect(summary.latestWindowEnd == Date(timeIntervalSince1970: 700))
    }

    @Test
    func policyDefaultsAndThresholdHelpersAreExplicit() {
        let policy = ReconciliationPolicy()

        #expect(policy.skewToleranceSeconds == 120)
        #expect(policy.minDrainPercent == 1)
        #expect(policy.minFiveHourDrainPercent == 1)
        #expect(policy.lowLocalTokenThreshold == 1_000)

        #expect(policy.isBelowNoiseFloor(weeklyDeltaPercent: 0, fiveHourDeltaPercent: 0))
        #expect(policy.isBelowNoiseFloor(weeklyDeltaPercent: nil, fiveHourDeltaPercent: nil))
        #expect(!policy.isBelowNoiseFloor(weeklyDeltaPercent: 2, fiveHourDeltaPercent: 0))
        #expect(!policy.isBelowNoiseFloor(weeklyDeltaPercent: nil, fiveHourDeltaPercent: 3))

        #expect(policy.hasLowLocalUsage(localTokens: 999))
        #expect(!policy.hasLowLocalUsage(localTokens: 1_000))
    }

    @Test
    func legacyUsageAuditEntryCanBeMappedWithoutPromptOrPathFields() throws {
        let legacyEntry = AnalyticsUsageAuditEntry(
            profileId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            profileName: "Alpha",
            windowStart: Date(timeIntervalSince1970: 100),
            windowEnd: Date(timeIntervalSince1970: 200),
            weeklyDropPercent: 5,
            fiveHourDropPercent: 3,
            localTokens: 42,
            localSessionCount: 2,
            idleWindow: false,
            status: .weakAttribution
        )

        let entry = ReconciliationEntry(legacyAuditEntry: legacyEntry)
        let payload = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(entry)
        ) as? [String: Any]

        #expect(entry.profileId == legacyEntry.profileId)
        #expect(entry.profileName == "Alpha")
        #expect(entry.windowStart == legacyEntry.windowStart)
        #expect(entry.windowEnd == legacyEntry.windowEnd)
        #expect(entry.providerWeeklyDeltaPercent == 5)
        #expect(entry.providerFiveHourDeltaPercent == 3)
        #expect(entry.localTokens == 42)
        #expect(entry.matchedSessionIds == [])
        #expect(entry.status == .weakAttribution)
        #expect(entry.reasonCode == .lowLocalUsage)
        #expect(entry.confidence == .medium)

        #expect(payload?["promptPreview"] == nil)
        #expect(payload?["projectPath"] == nil)
    }
}
