import Foundation
import Testing
@testable import CodexSwitcher

struct ReconciliationEngineTests {
    @Test
    func makeReportMarksIncompleteSamplesAsIgnored() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let profile = Profile(alias: "Alpha", email: "alpha@example.com", accountId: "acct-a", addedAt: now)
        let engine = ReconciliationEngine(now: { now })

        let report = engine.makeReport(
            range: .twentyFourHours,
            profiles: [profile],
            records: [],
            auditSamples: [
                profile.id: [
                    RateLimitAuditSample(
                        timestamp: now.addingTimeInterval(-3600),
                        weeklyRemainingPercent: 90,
                        fiveHourRemainingPercent: 80,
                        limitReached: false
                    ),
                    RateLimitAuditSample(
                        timestamp: now.addingTimeInterval(-1800),
                        weeklyRemainingPercent: nil,
                        fiveHourRemainingPercent: 70,
                        limitReached: false
                    )
                ]
            ]
        )

        let entry = try #require(report.entries.first)
        #expect(entry.status == .ignored)
        #expect(entry.reasonCode == .missingProviderSample)
        #expect(entry.providerWeeklyDeltaPercent == nil)
        #expect(entry.providerFiveHourDeltaPercent == 10)
        #expect(report.summary.ignoredCount == 1)
        #expect(report.summary.unexplainedCount == 0)
    }

    @Test
    func makeReportMarksCounterJumpsAsIgnored() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let profile = Profile(alias: "Alpha", email: "alpha@example.com", accountId: "acct-a", addedAt: now)
        let engine = ReconciliationEngine(now: { now })

        let report = engine.makeReport(
            range: .twentyFourHours,
            profiles: [profile],
            records: [],
            auditSamples: [
                profile.id: [
                    RateLimitAuditSample(
                        timestamp: now.addingTimeInterval(-3600),
                        weeklyRemainingPercent: 20,
                        fiveHourRemainingPercent: 10,
                        limitReached: true
                    ),
                    RateLimitAuditSample(
                        timestamp: now.addingTimeInterval(-1800),
                        weeklyRemainingPercent: 95,
                        fiveHourRemainingPercent: 90,
                        limitReached: false
                    )
                ]
            ]
        )

        let entry = try #require(report.entries.first)
        #expect(entry.status == .ignored)
        #expect(entry.reasonCode == .sampleResetOrCounterJump)
        #expect(entry.providerWeeklyDeltaPercent == nil)
        #expect(entry.providerFiveHourDeltaPercent == nil)
        #expect(report.summary.ignoredCount == 1)
    }

    @Test
    func makeReportAssignsEachLocalRecordToOnlyOneNearestWindow() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let profile = Profile(alias: "Alpha", email: "alpha@example.com", accountId: "acct-a", addedAt: now)
        let engine = ReconciliationEngine(
            policy: ReconciliationPolicy(skewToleranceSeconds: 120),
            now: { now }
        )

        let record = AnalyticsUsageRecord(
            timestamp: now.addingTimeInterval(-3_590),
            profileId: profile.id,
            projectPath: "/tmp/project",
            projectName: "project",
            sessionId: "session-1",
            model: "gpt-5",
            inputTokens: 1_500,
            cachedInputTokens: 0,
            outputTokens: 700
        )

        let report = engine.makeReport(
            range: .twentyFourHours,
            profiles: [profile],
            records: [record],
            auditSamples: [
                profile.id: [
                    RateLimitAuditSample(
                        timestamp: now.addingTimeInterval(-7_200),
                        weeklyRemainingPercent: 90,
                        fiveHourRemainingPercent: 80,
                        limitReached: false
                    ),
                    RateLimitAuditSample(
                        timestamp: now.addingTimeInterval(-3_600),
                        weeklyRemainingPercent: 84,
                        fiveHourRemainingPercent: 70,
                        limitReached: false
                    ),
                    RateLimitAuditSample(
                        timestamp: now.addingTimeInterval(-1_800),
                        weeklyRemainingPercent: 80,
                        fiveHourRemainingPercent: 68,
                        limitReached: false
                    )
                ]
            ]
        )

        #expect(report.entries.count == 2)
        #expect(report.entries[0].windowEnd == now.addingTimeInterval(-1_800))
        #expect(report.entries[0].matchedSessionIds == ["session-1"])
        #expect(report.entries[0].localTokens == 2_200)
        #expect(report.entries[1].windowEnd == now.addingTimeInterval(-3_600))
        #expect(report.entries[1].matchedSessionIds == [])
        #expect(report.entries[1].localTokens == 0)
        #expect(report.entries.reduce(0) { $0 + $1.localTokens } == 2_200)
    }

    @Test
    func makeReportEmitsWeakAttributionForLowLocalUsage() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let profile = Profile(alias: "Alpha", email: "alpha@example.com", accountId: "acct-a", addedAt: now)
        let engine = ReconciliationEngine(
            policy: ReconciliationPolicy(lowLocalTokenThreshold: 1_000),
            now: { now }
        )

        let report = engine.makeReport(
            range: .twentyFourHours,
            profiles: [profile],
            records: [
                AnalyticsUsageRecord(
                    timestamp: now.addingTimeInterval(-3_540),
                    profileId: profile.id,
                    projectPath: "/tmp/project",
                    projectName: "project",
                    sessionId: "session-1",
                    model: "gpt-5",
                    inputTokens: 150,
                    cachedInputTokens: 0,
                    outputTokens: 100
                )
            ],
            auditSamples: [
                profile.id: [
                    RateLimitAuditSample(
                        timestamp: now.addingTimeInterval(-3_600),
                        weeklyRemainingPercent: 80,
                        fiveHourRemainingPercent: 75,
                        limitReached: false
                    ),
                    RateLimitAuditSample(
                        timestamp: now.addingTimeInterval(-1_800),
                        weeklyRemainingPercent: 70,
                        fiveHourRemainingPercent: 60,
                        limitReached: false
                    )
                ]
            ]
        )

        let entry = try #require(report.entries.first)
        #expect(entry.status == .weakAttribution)
        #expect(entry.reasonCode == .switchBoundaryOverlap)
        #expect(entry.confidence == .medium)
        #expect(entry.localTokens == 250)
        #expect(entry.matchedSessionIds == ["session-1"])
    }

    @Test
    func makeReportEmitsUnexplainedIdleDrainWhenNoLocalUsageExists() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let profile = Profile(alias: "Alpha", email: "alpha@example.com", accountId: "acct-a", addedAt: now)
        let engine = ReconciliationEngine(now: { now })

        let report = engine.makeReport(
            range: .twentyFourHours,
            profiles: [profile],
            records: [],
            auditSamples: [
                profile.id: [
                    RateLimitAuditSample(
                        timestamp: now.addingTimeInterval(-3_600),
                        weeklyRemainingPercent: 80,
                        fiveHourRemainingPercent: 75,
                        limitReached: false
                    ),
                    RateLimitAuditSample(
                        timestamp: now.addingTimeInterval(-1_800),
                        weeklyRemainingPercent: 73,
                        fiveHourRemainingPercent: 63,
                        limitReached: false
                    )
                ]
            ]
        )

        let entry = try #require(report.entries.first)
        #expect(entry.status == .unexplained)
        #expect(entry.reasonCode == .idleDrain)
        #expect(entry.confidence == .low)
        #expect(entry.localTokens == 0)
        #expect(entry.matchedSessionIds == [])
        #expect(report.summary.unexplainedCount == 1)
        #expect(report.summary.idleDrainCount == 1)
    }

    @Test
    func makeReportIgnoresNoiseFloorWindowsAndSkipsWindowsBeforeCutoff() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let profile = Profile(alias: "Alpha", email: "alpha@example.com", accountId: "acct-a", addedAt: now)
        let engine = ReconciliationEngine(
            policy: ReconciliationPolicy(minDrainPercent: 2, minFiveHourDrainPercent: 2),
            now: { now }
        )

        let report = engine.makeReport(
            range: .twentyFourHours,
            profiles: [profile],
            records: [],
            auditSamples: [
                profile.id: [
                    RateLimitAuditSample(
                        timestamp: now.addingTimeInterval(-30 * 3600),
                        weeklyRemainingPercent: 90,
                        fiveHourRemainingPercent: 90,
                        limitReached: false
                    ),
                    RateLimitAuditSample(
                        timestamp: now.addingTimeInterval(-26 * 3600),
                        weeklyRemainingPercent: 70,
                        fiveHourRemainingPercent: 70,
                        limitReached: false
                    ),
                    RateLimitAuditSample(
                        timestamp: now.addingTimeInterval(-3_600),
                        weeklyRemainingPercent: 70,
                        fiveHourRemainingPercent: 70,
                        limitReached: false
                    ),
                    RateLimitAuditSample(
                        timestamp: now.addingTimeInterval(-1_800),
                        weeklyRemainingPercent: 69,
                        fiveHourRemainingPercent: 70,
                        limitReached: false
                    )
                ]
            ]
        )

        #expect(report.entries.map(\.windowEnd) == [now.addingTimeInterval(-1_800)])
        #expect(report.entries.first?.status == .ignored)
        #expect(report.entries.first?.reasonCode == .belowNoiseFloor)
        #expect(report.summary.totalWindowCount == 1)
    }
}
