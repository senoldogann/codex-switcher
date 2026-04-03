import Foundation
import Testing
@testable import CodexSwitcher

struct AnalyticsEngineTests {
    @Test
    func snapshotFiltersBySelectedRange() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let profileA = Profile(alias: "Alpha", email: "alpha@example.com", accountId: "acct-a", addedAt: now)
        let profileB = Profile(alias: "Beta", email: "beta@example.com", accountId: "acct-b", addedAt: now)

        let records = [
            AnalyticsUsageRecord(
                timestamp: now.addingTimeInterval(-2 * 3600),
                profileId: profileA.id,
                projectPath: "/tmp/current",
                projectName: "current",
                sessionId: "s-1",
                model: "gpt-5",
                inputTokens: 120,
                cachedInputTokens: 20,
                outputTokens: 30
            ),
            AnalyticsUsageRecord(
                timestamp: now.addingTimeInterval(-3 * 24 * 3600),
                profileId: profileB.id,
                projectPath: "/tmp/week",
                projectName: "week",
                sessionId: "s-2",
                model: "gpt-5-mini",
                inputTokens: 80,
                cachedInputTokens: 0,
                outputTokens: 20
            ),
            AnalyticsUsageRecord(
                timestamp: now.addingTimeInterval(-20 * 24 * 3600),
                profileId: profileA.id,
                projectPath: "/tmp/month",
                projectName: "month",
                sessionId: "s-3",
                model: "gpt-5",
                inputTokens: 200,
                cachedInputTokens: 0,
                outputTokens: 50
            ),
            AnalyticsUsageRecord(
                timestamp: now.addingTimeInterval(-40 * 24 * 3600),
                profileId: profileB.id,
                projectPath: "/tmp/archive",
                projectName: "archive",
                sessionId: "s-4",
                model: "gpt-5-pro",
                inputTokens: 100,
                cachedInputTokens: 0,
                outputTokens: 10
            )
        ]

        let engine = AnalyticsEngine(now: { now }, calendar: Calendar(identifier: .gregorian))

        let daySnapshot = engine.makeSnapshot(
            range: .twentyFourHours,
            profiles: [profileA, profileB],
            usageRecords: records,
            rateLimits: [:],
            rateLimitHealth: [:],
            forecasts: [:]
        )
        let weekSnapshot = engine.makeSnapshot(
            range: .sevenDays,
            profiles: [profileA, profileB],
            usageRecords: records,
            rateLimits: [:],
            rateLimitHealth: [:],
            forecasts: [:]
        )
        let monthSnapshot = engine.makeSnapshot(
            range: .thirtyDays,
            profiles: [profileA, profileB],
            usageRecords: records,
            rateLimits: [:],
            rateLimitHealth: [:],
            forecasts: [:]
        )
        let allTimeSnapshot = engine.makeSnapshot(
            range: .allTime,
            profiles: [profileA, profileB],
            usageRecords: records,
            rateLimits: [:],
            rateLimitHealth: [:],
            forecasts: [:]
        )

        #expect(daySnapshot.summary.totalTokens == 150)
        #expect(weekSnapshot.summary.totalTokens == 250)
        #expect(monthSnapshot.summary.totalTokens == 500)
        #expect(allTimeSnapshot.summary.totalTokens == 610)
        #expect(daySnapshot.projectBreakdown.map(\.name) == ["current"])
        #expect(Set(weekSnapshot.projectBreakdown.map(\.name)) == Set(["current", "week"]))
        #expect(Set(monthSnapshot.projectBreakdown.map(\.name)) == Set(["current", "week", "month"]))
        #expect(Set(allTimeSnapshot.projectBreakdown.map(\.name)) == Set(["current", "week", "month", "archive"]))
    }

    @Test
    func snapshotGeneratesAlertsAndDegradedConfidenceForStaleHighRiskData() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let profileA = Profile(alias: "Alpha", email: "alpha@example.com", accountId: "acct-a", addedAt: now)
        let profileB = Profile(alias: "Beta", email: "beta@example.com", accountId: "acct-b", addedAt: now)

        var records: [AnalyticsUsageRecord] = []
        for dayOffset in 1...6 {
            records.append(
                AnalyticsUsageRecord(
                    timestamp: now.addingTimeInterval(-Double(dayOffset) * 24 * 3600),
                    profileId: profileA.id,
                    projectPath: "/tmp/baseline",
                    projectName: "baseline",
                    sessionId: "baseline-\(dayOffset)",
                    model: "gpt-5-mini",
                    inputTokens: 200_000,
                    cachedInputTokens: 0,
                    outputTokens: 20_000
                )
            )
        }

        records.append(
            AnalyticsUsageRecord(
                timestamp: now.addingTimeInterval(-2 * 3600),
                profileId: profileA.id,
                projectPath: "/tmp/hot-project",
                projectName: "hot-project",
                sessionId: "spike",
                model: "gpt-5-pro",
                inputTokens: 600_000,
                cachedInputTokens: 0,
                outputTokens: 120_000
            )
        )

        let rateLimits: [UUID: RateLimitInfo] = [
            profileA.id: RateLimitInfo(
                planType: "plus",
                allowed: true,
                limitReached: false,
                weeklyUsedPercent: 92,
                weeklyResetAt: nil,
                fiveHourRemainingPercent: 12,
                fiveHourResetAt: nil,
            ),
            profileB.id: RateLimitInfo(
                planType: "plus",
                allowed: true,
                limitReached: false,
                weeklyUsedPercent: 35,
                weeklyResetAt: nil,
                fiveHourRemainingPercent: 70,
                fiveHourResetAt: nil,
            )
        ]

        let rateLimitHealth: [UUID: RateLimitHealthStatus] = [
            profileA.id: RateLimitHealthStatus(
                lastCheckedAt: now,
                lastSuccessfulFetchAt: now.addingTimeInterval(-3600),
                lastFailedFetchAt: nil,
                lastHTTPStatusCode: nil,
                staleReason: nil,
                failureSummary: nil
            ),
            profileB.id: RateLimitHealthStatus(
                lastCheckedAt: now,
                lastSuccessfulFetchAt: now.addingTimeInterval(-48 * 3600),
                lastFailedFetchAt: now.addingTimeInterval(-1800),
                lastHTTPStatusCode: 401,
                staleReason: .unauthorized,
                failureSummary: "401 unauthorized"
            )
        ]

        let forecasts: [UUID: RateLimitForecast] = [
            profileA.id: RateLimitForecast(
                riskLevel: .critical,
                estimatedTimeToExhaustion: now.addingTimeInterval(6 * 3600),
                pacePerHour: 90_000
            )
        ]

        let engine = AnalyticsEngine(now: { now }, calendar: Calendar(identifier: .gregorian))
        let snapshot = engine.makeSnapshot(
            range: .sevenDays,
            profiles: [profileA, profileB],
            usageRecords: records,
            rateLimits: rateLimits,
            rateLimitHealth: rateLimitHealth,
            forecasts: forecasts
        )

        #expect(snapshot.summary.activeAlertCount >= 4)
        #expect(snapshot.dataQuality.confidence == .low)
        #expect(snapshot.alerts.contains(where: { $0.kind == .costSpike }))
        #expect(snapshot.alerts.contains(where: { $0.kind == .projectConcentration }))
        #expect(snapshot.alerts.contains(where: { $0.kind == .limitPressure }))
        #expect(snapshot.alerts.contains(where: { $0.kind == .staleData }))
        #expect(snapshot.limitPressure.first?.profileId == profileA.id)
        #expect(snapshot.limitPressure.contains(where: { $0.profileId == profileB.id && $0.confidence == .low }))
    }
}
