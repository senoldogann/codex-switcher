import Foundation

struct PowerUserRecommendation: Equatable, Sendable {
    let title: String
    let detail: String
}

enum PowerUserRecommendationEngine {
    static func build(
        automation: AutomationConfidenceSummary,
        diagnostics: DiagnosticsSummary,
        workflow: WorkflowSummary
    ) -> PowerUserRecommendation? {
        if automation.stuckPendingSwitch {
            return PowerUserRecommendation(
                title: "Review pending switch",
                detail: automation.highlight
            )
        }

        if diagnostics.criticalCount > 0 {
            return PowerUserRecommendation(
                title: "Open diagnostics",
                detail: "\(diagnostics.criticalCount) critical diagnostics event requires attention."
            )
        }

        if automation.staleProfileCount > 0 {
            return PowerUserRecommendation(
                title: "Re-login stale accounts",
                detail: automation.highlight
            )
        }

        if workflow.openSpawnEdges > 0 {
            return PowerUserRecommendation(
                title: "Inspect active workflow edges",
                detail: "\(workflow.openSpawnEdges) open thread spawn edge is still active."
            )
        }

        return nil
    }
}
