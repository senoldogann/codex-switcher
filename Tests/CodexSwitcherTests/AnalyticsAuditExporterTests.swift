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
        let data = try #require(json.data(using: String.Encoding.utf8))
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        let range = try #require(object["range"] as? String)
        let summary = try #require(object["usageAuditSummary"] as? [String: Any])
        let entries = try #require(object["usageAuditEntries"] as? [[String: Any]])
        let timeline = try #require(object["usageAuditTimeline"] as? [[String: Any]])
        let firstEntry = try #require(entries.first)
        let firstTimelinePoint = try #require(timeline.first)

        #expect(range == "sevenDays")
        #expect(summary["idleDrainCount"] as? Int == 1)
        #expect(firstEntry["status"] as? String == "unattributed")
        #expect(firstEntry["idleWindow"] as? Bool == true)
        #expect(firstTimelinePoint["weeklyDropPercent"] as? Int == 8)
    }

    @Test
    func buildCSVIncludesReconciliationLedgerColumns() {
        let entries = [
            ReconciliationEntry(
                profileId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                profileName: #"acct "alpha""#,
                windowStart: Date(timeIntervalSince1970: 1_700_000_000),
                windowEnd: Date(timeIntervalSince1970: 1_700_000_600),
                providerWeeklyDeltaPercent: 8,
                providerFiveHourDeltaPercent: nil,
                localTokens: 120,
                matchedSessionIds: ["s-1", "s-2"],
                status: .weakAttribution,
                reasonCode: .switchBoundaryOverlap,
                confidence: .medium
            )
        ]

        let csv = AnalyticsAuditExporter.buildCSV(for: entries)

        #expect(csv.contains("Profile,Status,Reason,Confidence,Weekly Delta %,5-Hour Delta %,Local Tokens,Matched Sessions,Window Start,Window End"))
        #expect(csv.contains(#""acct ""alpha""","weakAttribution","switch_boundary_overlap","medium",8,,120,"s-1 s-2","#))
        #expect(csv.hasSuffix("\n"))
    }

    @Test
    func buildJSONIncludesReconciliationLedgerAndPolicyWithoutPromptOrPath() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_700_001_000)
        let entry = ReconciliationEntry(
            profileId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            profileName: "Alpha",
            windowStart: Date(timeIntervalSince1970: 1_700_000_000),
            windowEnd: Date(timeIntervalSince1970: 1_700_000_600),
            providerWeeklyDeltaPercent: 8,
            providerFiveHourDeltaPercent: 12,
            localTokens: 120,
            matchedSessionIds: ["s-1"],
            status: .weakAttribution,
            reasonCode: .lowLocalUsage,
            confidence: .medium
        )
        let snapshot = AnalyticsSnapshot(
            generatedAt: generatedAt,
            range: .sevenDays,
            summary: AnalyticsSummary(
                totalTokens: 120,
                estimatedTotalCost: 0.25,
                busiestAccountName: "Alpha",
                busiestAccountTokens: 120,
                mostExpensiveProjectName: nil,
                mostExpensiveProjectCost: 0,
                activeAlertCount: 0
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
            usageAuditSummary: .empty,
            usageAuditEntries: [],
            usageAuditTimeline: [],
            reconciliationSummary: ReconciliationSummary(entries: [entry]),
            reconciliationEntries: [entry],
            reconciliationPolicy: ReconciliationPolicy(skewToleranceSeconds: 120, minDrainPercent: 1, minFiveHourDrainPercent: 5, lowLocalTokenThreshold: 2_000),
            alerts: [],
            dataQuality: AnalyticsDataQuality(
                confidence: .high,
                staleProfileIds: [],
                lastSuccessfulFetch: generatedAt,
                message: nil
            )
        )

        let json = try AnalyticsAuditExporter.buildJSON(for: snapshot)
        let data = try #require(json.data(using: String.Encoding.utf8))
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        let summary = try #require(object["reconciliationSummary"] as? [String: Any])
        let entries = try #require(object["reconciliationEntries"] as? [[String: Any]])
        let entryPayload = try #require(entries.first)
        let policy = try #require(object["reconciliationPolicy"] as? [String: Any])

        #expect(summary["weakAttributionCount"] as? Int == 1)
        #expect(entryPayload["status"] as? String == "weakAttribution")
        #expect(entryPayload["reasonCode"] as? String == "low_local_usage")
        #expect(entryPayload["confidence"] as? String == "medium")
        #expect((entryPayload["matchedSessionIds"] as? [String]) == ["s-1"])
        #expect(policy["skewToleranceSeconds"] as? Int == 120)
        #expect(policy["minFiveHourDrainPercent"] as? Int == 5)

        #expect(json.contains("promptPreview") == false)
        #expect(json.contains("projectPath") == false)
    }
}
