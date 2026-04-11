import Foundation

enum DiagnosticsEventSeverity: String, Codable, Equatable, Sendable {
    case info
    case warning
    case critical
}

enum DiagnosticsEventKind: String, Codable, Equatable, Sendable {
    case switchDecision
    case switchTimeline
    case reconciliation
    case alert
    case dataQuality
}

struct DiagnosticsEvent: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let timestamp: Date
    let kind: DiagnosticsEventKind
    let severity: DiagnosticsEventSeverity
    let title: String
    let detail: String
    let subject: String?
}

struct DiagnosticsSummary: Equatable, Sendable {
    let totalCount: Int
    let warningCount: Int
    let criticalCount: Int
    let latestEventAt: Date?

    static let empty = DiagnosticsSummary(
        totalCount: 0,
        warningCount: 0,
        criticalCount: 0,
        latestEventAt: nil
    )
}
