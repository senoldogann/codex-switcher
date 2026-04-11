import Foundation
import Testing
@testable import CodexSwitcher

struct DiagnosticsEngineTests {
    @Test
    func makeTimelineCombinesSourcesAndSortsNewestFirst() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let decision = SwitchDecisionRecord(
            id: UUID(),
            timestamp: now.addingTimeInterval(-60),
            source: .automatic,
            outcome: .blocked,
            requestedProfileId: nil,
            requestedProfileName: nil,
            chosenProfileId: nil,
            chosenProfileName: "Alpha",
            reason: "Limit reached",
            detail: "Target account could not be verified.",
            overrideApplied: false,
            readiness: []
        )
        let timeline = SwitchTimelineEvent(
            id: UUID(),
            timestamp: now.addingTimeInterval(-30),
            stage: .fallbackRestart,
            targetProfileName: "Alpha",
            reason: "Limit reached",
            detail: "Fallback restart applied.",
            waitDurationSeconds: nil,
            verificationDurationSeconds: 4
        )
        let entry = ReconciliationEntry(
            profileId: UUID(),
            profileName: "Alpha",
            windowStart: now.addingTimeInterval(-120),
            windowEnd: now.addingTimeInterval(-10),
            providerWeeklyDeltaPercent: 9,
            providerFiveHourDeltaPercent: 4,
            localTokens: 0,
            matchedSessionIds: [],
            status: .unexplained,
            reasonCode: .idleDrain,
            confidence: .low
        )
        let alert = AnalyticsAlert(
            kind: .unattributedDrain,
            severity: .critical,
            title: "Unexplained provider drain",
            message: "Provider capacity dropped without matching local usage."
        )
        let dataQuality = AnalyticsDataQuality(
            confidence: .low,
            staleProfileIds: [],
            lastSuccessfulFetch: now.addingTimeInterval(-300),
            message: "Rate-limit data is degraded."
        )

        let events = DiagnosticsEngine().makeTimeline(
            switchDecisions: [decision],
            switchTimeline: [timeline],
            reconciliationEntries: [entry],
            alerts: [alert],
            dataQuality: dataQuality,
            generatedAt: now
        )

        #expect(events.count == 5)
        #expect(events.first?.kind == .dataQuality || events.first?.kind == .alert)
        #expect(events.contains(where: { $0.kind == .reconciliation && $0.severity == .critical }))
        #expect(events.contains(where: { $0.kind == .switchDecision }))
    }

    @Test
    func makeSummaryCountsWarningAndCriticalEvents() {
        let now = Date(timeIntervalSince1970: 1_760_000_100)
        let events = [
            DiagnosticsEvent(
                id: "1",
                timestamp: now,
                kind: .alert,
                severity: .critical,
                title: "Critical",
                detail: "detail",
                subject: nil
            ),
            DiagnosticsEvent(
                id: "2",
                timestamp: now.addingTimeInterval(-10),
                kind: .switchTimeline,
                severity: .warning,
                title: "Warning",
                detail: "detail",
                subject: nil
            ),
            DiagnosticsEvent(
                id: "3",
                timestamp: now.addingTimeInterval(-20),
                kind: .switchDecision,
                severity: .info,
                title: "Info",
                detail: "detail",
                subject: nil
            )
        ]

        let summary = DiagnosticsEngine().makeSummary(events: events)

        #expect(summary.totalCount == 3)
        #expect(summary.warningCount == 1)
        #expect(summary.criticalCount == 1)
        #expect(summary.latestEventAt == now)
    }
}
