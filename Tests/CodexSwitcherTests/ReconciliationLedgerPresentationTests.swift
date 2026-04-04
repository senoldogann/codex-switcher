import Foundation
import Testing
@testable import CodexSwitcher

struct ReconciliationLedgerPresentationTests {
    @Test
    func sectionStateBuildsEmptyStateFromSnapshot() {
        let snapshot = AnalyticsSnapshot.empty(for: .sevenDays)

        let state = ReconciliationLedgerSectionState(
            snapshot: snapshot,
            sortOrder: .highestRisk
        )

        #expect(state.isEmpty == true)
        #expect(state.entries.isEmpty)
        #expect(state.defaultSelectedEntryID == nil)
        #expect(ReconciliationLedgerPresentation.emptyMessage(for: state).isEmpty == false)
    }

    @Test
    func sectionStateSortsHighestRiskBeforeNewest() {
        let entries = sampleEntries()
        let snapshot = makeSnapshot(entries: entries)

        let highestRisk = ReconciliationLedgerSectionState(
            snapshot: snapshot,
            sortOrder: .highestRisk
        )
        let newest = ReconciliationLedgerSectionState(
            snapshot: snapshot,
            sortOrder: .newest
        )

        #expect(highestRisk.entries.map(\.status) == [.unexplained, .weakAttribution, .explained, .ignored])
        #expect(newest.entries.map(\.windowEnd) == entries.map(\.windowEnd).sorted(by: >))
    }

    @Test
    func summaryItemsReflectExplainedUnexplainedAndIgnoredCounts() {
        let summary = ReconciliationSummary(entries: sampleEntries())

        let items = ReconciliationLedgerPresentation.summaryItems(from: summary)

        #expect(items.first(where: { $0.id == "explained" })?.value == 1)
        #expect(items.first(where: { $0.id == "weak" })?.value == 1)
        #expect(items.first(where: { $0.id == "unexplained" })?.value == 1)
        #expect(items.first(where: { $0.id == "ignored" })?.value == 1)
    }

    @Test
    func labelsAndNotesStayStableForReasonStatusAndConfidence() {
        #expect(ReconciliationLedgerPresentation.statusLabel(.ignored).isEmpty == false)
        #expect(ReconciliationLedgerPresentation.reasonLabel(.sampleResetOrCounterJump).isEmpty == false)
        #expect(ReconciliationLedgerPresentation.confidenceLabel(.medium).isEmpty == false)

        let boundaryEntry = ReconciliationEntry(
            profileId: UUID(),
            profileName: "Alpha",
            windowStart: Date(timeIntervalSince1970: 1_760_000_000),
            windowEnd: Date(timeIntervalSince1970: 1_760_000_600),
            providerWeeklyDeltaPercent: 6,
            providerFiveHourDeltaPercent: 9,
            localTokens: 400,
            matchedSessionIds: ["s-1"],
            status: .weakAttribution,
            reasonCode: .switchBoundaryOverlap,
            confidence: .medium
        )

        #expect(ReconciliationLedgerPresentation.detailMessage(for: boundaryEntry).isEmpty == false)
        let note = ReconciliationLedgerPresentation.supplementalNote(for: boundaryEntry)
        #expect(note?.isEmpty == false)
    }

    private func makeSnapshot(entries: [ReconciliationEntry]) -> AnalyticsSnapshot {
        AnalyticsSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_760_001_000),
            range: .sevenDays,
            summary: AnalyticsSummary(
                totalTokens: 0,
                estimatedTotalCost: 0,
                busiestAccountName: nil,
                busiestAccountTokens: 0,
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
            reconciliationSummary: ReconciliationSummary(entries: entries),
            reconciliationEntries: entries,
            reconciliationPolicy: ReconciliationPolicy(),
            alerts: [],
            dataQuality: AnalyticsDataQuality(
                confidence: .high,
                staleProfileIds: [],
                lastSuccessfulFetch: nil,
                message: nil
            )
        )
    }

    private func sampleEntries() -> [ReconciliationEntry] {
        [
            ReconciliationEntry(
                profileId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                profileName: "Explained",
                windowStart: Date(timeIntervalSince1970: 1_760_000_000),
                windowEnd: Date(timeIntervalSince1970: 1_760_000_600),
                providerWeeklyDeltaPercent: 3,
                providerFiveHourDeltaPercent: 4,
                localTokens: 3_000,
                matchedSessionIds: ["s-1"],
                status: .explained,
                reasonCode: .matchedActivity,
                confidence: .high
            ),
            ReconciliationEntry(
                profileId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                profileName: "Weak",
                windowStart: Date(timeIntervalSince1970: 1_760_000_700),
                windowEnd: Date(timeIntervalSince1970: 1_760_001_100),
                providerWeeklyDeltaPercent: 7,
                providerFiveHourDeltaPercent: 10,
                localTokens: 500,
                matchedSessionIds: ["s-2"],
                status: .weakAttribution,
                reasonCode: .lowLocalUsage,
                confidence: .medium
            ),
            ReconciliationEntry(
                profileId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                profileName: "Unexplained",
                windowStart: Date(timeIntervalSince1970: 1_760_001_200),
                windowEnd: Date(timeIntervalSince1970: 1_760_001_800),
                providerWeeklyDeltaPercent: 12,
                providerFiveHourDeltaPercent: 12,
                localTokens: 0,
                matchedSessionIds: [],
                status: .unexplained,
                reasonCode: .idleDrain,
                confidence: .low
            ),
            ReconciliationEntry(
                profileId: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                profileName: "Ignored",
                windowStart: Date(timeIntervalSince1970: 1_760_001_900),
                windowEnd: Date(timeIntervalSince1970: 1_760_002_400),
                providerWeeklyDeltaPercent: nil,
                providerFiveHourDeltaPercent: nil,
                localTokens: 0,
                matchedSessionIds: [],
                status: .ignored,
                reasonCode: .missingProviderSample,
                confidence: .low
            )
        ]
    }
}
