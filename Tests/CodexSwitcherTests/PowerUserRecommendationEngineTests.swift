import Foundation
import Testing
@testable import CodexSwitcher

struct PowerUserRecommendationEngineTests {
    @Test
    func recommendationPrefersCriticalDiagnostics() {
        let recommendation = PowerUserRecommendationEngine.build(
            automation: AutomationConfidenceSummary(
                status: .healthy,
                highlight: "healthy",
                staleProfileCount: 0,
                fallbackRestartCount: 0,
                seamlessSuccessCount: 1,
                blockedDecisionCount: 0,
                haltedDecisionCount: 0,
                stuckPendingSwitch: false,
                lastVerifiedSwitchAt: nil
            ),
            diagnostics: DiagnosticsSummary(
                totalCount: 3,
                warningCount: 1,
                criticalCount: 2,
                latestEventAt: Date()
            ),
            workflow: .empty
        )

        #expect(recommendation?.title == "Open diagnostics")
    }

    @Test
    func recommendationFallsBackToWorkflowEdges() {
        let recommendation = PowerUserRecommendationEngine.build(
            automation: AutomationConfidenceSummary.empty,
            diagnostics: .empty,
            workflow: WorkflowSummary(
                totalActiveThreads: 2,
                totalThreadTokens: 1000,
                openSpawnEdges: 1,
                repoInsights: [],
                recentThreads: []
            )
        )

        #expect(recommendation?.title == "Inspect active workflow edges")
    }
}
