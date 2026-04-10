import Foundation
import Testing
@testable import CodexSwitcher

struct AutomationAlertPolicyTests {
    @Test
    func returnsNilForHealthySummary() {
        let summary = AutomationConfidenceSummary.empty
        let alert = AutomationAlertPolicy.nextAlert(
            summary: summary,
            previousFingerprint: nil
        )

        #expect(alert == nil)
    }

    @Test
    func emitsAlertWhenSummaryTurnsWarning() {
        let summary = AutomationConfidenceSummary(
            status: .warning,
            highlight: "1 account needs re-login attention.",
            staleProfileCount: 1,
            fallbackRestartCount: 0,
            seamlessSuccessCount: 2,
            blockedDecisionCount: 0,
            haltedDecisionCount: 0,
            stuckPendingSwitch: false,
            lastVerifiedSwitchAt: nil
        )

        let alert = AutomationAlertPolicy.nextAlert(
            summary: summary,
            previousFingerprint: nil
        )

        #expect(alert?.severity == .warning)
        #expect(alert?.title == Str.automationWarningTitle)
    }

    @Test
    func suppressesDuplicateAlertsForSameFingerprint() {
        let summary = AutomationConfidenceSummary(
            status: .critical,
            highlight: "Pending switch has been stuck for 95s.",
            staleProfileCount: 0,
            fallbackRestartCount: 1,
            seamlessSuccessCount: 0,
            blockedDecisionCount: 0,
            haltedDecisionCount: 0,
            stuckPendingSwitch: true,
            lastVerifiedSwitchAt: nil
        )

        let first = AutomationAlertPolicy.nextAlert(summary: summary, previousFingerprint: nil)
        let second = AutomationAlertPolicy.nextAlert(
            summary: summary,
            previousFingerprint: first?.fingerprint
        )

        #expect(first?.severity == .critical)
        #expect(second == nil)
    }
}
