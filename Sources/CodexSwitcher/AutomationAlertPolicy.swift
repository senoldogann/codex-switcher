import Foundation

enum AutomationAlertPolicy {
    static func nextAlert(
        summary: AutomationConfidenceSummary,
        previousFingerprint: String?
    ) -> AutomationAlert? {
        guard summary.status != .healthy else { return nil }

        let severity: AutomationAlertSeverity = summary.status == .critical ? .critical : .warning
        let title: String = {
            switch severity {
            case .critical:
                return "Automation needs immediate attention"
            case .warning:
                return "Automation needs attention"
            }
        }()

        let fingerprint = [
            summary.status.rawValue,
            summary.highlight,
            "\(summary.staleProfileCount)",
            "\(summary.fallbackRestartCount)",
            "\(summary.stuckPendingSwitch)"
        ].joined(separator: "|")

        guard fingerprint != previousFingerprint else { return nil }

        return AutomationAlert(
            fingerprint: fingerprint,
            severity: severity,
            title: title,
            body: summary.highlight
        )
    }
}
