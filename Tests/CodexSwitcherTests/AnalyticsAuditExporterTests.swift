import Foundation
import Testing
@testable import CodexSwitcher

struct AnalyticsAuditExporterTests {
    @Test
    func buildCSVIncludesIdleAndStatusColumns() {
        let entries = [
            AnalyticsUsageAuditEntry(
                profileId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                profileName: #"acct "alpha""#,
                windowStart: Date(timeIntervalSince1970: 1_700_000_000),
                windowEnd: Date(timeIntervalSince1970: 1_700_000_600),
                weeklyDropPercent: 8,
                fiveHourDropPercent: 12,
                localTokens: 0,
                localSessionCount: 0,
                idleWindow: true,
                status: .unattributed
            )
        ]

        let csv = AnalyticsAuditExporter.buildCSV(for: entries)

        #expect(csv.contains("Profile,Status,Idle Window,Weekly Drop %,5-Hour Drop %,Local Tokens,Local Sessions,Window Start,Window End"))
        #expect(csv.contains(#""acct ""alpha""","unattributed",true,8,12,0,0,"#))
        #expect(csv.hasSuffix("\n"))
    }

    @Test
    func buildJSONIncludesSummaryEntriesAndTimeline() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_700_001_000)
        let entry = AnalyticsUsageAuditEntry(
            profileId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            profileName: "Alpha",
            windowStart: Date(timeIntervalSince1970: 1_700_000_000),
            windowEnd: Date(timeIntervalSince1970: 1_700_000_600),
            weeklyDropPercent: 8,
            fiveHourDropPercent: 12,
            localTokens: 0,
            localSessionCount: 0,
            idleWindow: true,
            status: .unattributed
        )
        let snapshot = AnalyticsSnapshot(
            generatedAt: generatedAt,
            range: .sevenDays,
            summary: AnalyticsSummary(
                totalTokens: 1000,
                estimatedTotalCost: 1.25,
                busiestAccountName: "Alpha",
                busiestAccountTokens: 1000,
                mostExpensiveProjectName: "demo",
                mostExpensiveProjectCost: 1.25,
                activeAlertCount: 1
            ),
            tokenTrend: [],
            costTrend: [],
            dailyUsageByProfile: [:],
            accountBreakdown: [],
            projectBreakdown: [],
            modelBreakdown: [],
            projects: [],
            sessions: [],
            hourlyActivity: [],
            expensiveTurns: [],
            limitPressure: [],
            usageAuditSummary: AnalyticsUsageAuditSummary(
                explainedCount: 0,
                weakAttributionCount: 0,
                unattributedCount: 1,
                idleDrainCount: 1,
                totalDrainEvents: 1,
                latestEventAt: entry.windowEnd
            ),
            usageAuditEntries: [entry],
            usageAuditTimeline: [
                AnalyticsUsageAuditPoint(
                    timestamp: entry.windowEnd,
                    weeklyDropPercent: 8,
                    fiveHourDropPercent: 12,
                    localTokens: 0,
                    idleWindow: true,
                    status: .unattributed
                )
            ],
            alerts: [],
            dataQuality: AnalyticsDataQuality(
                confidence: .high,
                staleProfileIds: [],
                lastSuccessfulFetch: generatedAt,
                message: nil
            )
        )

        let json = try AnalyticsAuditExporter.buildJSON(for: snapshot)
        let data = try #require(json.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let range = object?["range"] as? String
        let summary = object?["usageAuditSummary"] as? [String: Any]
        let entries = object?["usageAuditEntries"] as? [[String: Any]]
        let timeline = object?["usageAuditTimeline"] as? [[String: Any]]

        #expect(range == "sevenDays")
        #expect(summary?["idleDrainCount"] as? Int == 1)
        #expect(entries?.first?["status"] as? String == "unattributed")
        #expect(entries?.first?["idleWindow"] as? Bool == true)
        #expect(timeline?.first?["weeklyDropPercent"] as? Int == 8)
    }
}
