import Foundation

struct AnalyticsUsageRecord: Identifiable, Equatable, Sendable {
    let timestamp: Date
    let profileId: UUID
    let projectPath: String
    let projectName: String
    let sessionId: String
    let model: String
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int

    var id: String {
        "\(sessionId)-\(timestamp.timeIntervalSince1970)-\(profileId.uuidString)-\(model)"
    }

    var totalTokens: Int { inputTokens + outputTokens }

    var usage: AccountTokenUsage {
        AccountTokenUsage(
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            reasoningTokens: 0,
            sessionCount: 0,
            modelUsage: [
                model: ModelTokenUsage(
                    inputTokens: inputTokens,
                    cachedInputTokens: cachedInputTokens,
                    outputTokens: outputTokens,
                    sessionCount: 0
                )
            ]
        )
    }
}

struct AnalyticsSessionTurnRecord: Identifiable, Equatable, Sendable {
    let promptPreview: String
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let timestamp: Date
    let model: String

    var id: String {
        "\(timestamp.timeIntervalSince1970)-\(model)-\(promptPreview)"
    }

    var totalTokens: Int { inputTokens + outputTokens }

    var usage: AccountTokenUsage {
        AccountTokenUsage(
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            reasoningTokens: 0,
            sessionCount: 0,
            modelUsage: [
                model: ModelTokenUsage(
                    inputTokens: inputTokens,
                    cachedInputTokens: cachedInputTokens,
                    outputTokens: outputTokens,
                    sessionCount: 0
                )
            ]
        )
    }
}

struct AnalyticsSessionRecord: Identifiable, Equatable, Sendable {
    let sessionId: String
    let projectPath: String
    let projectName: String
    let firstPrompt: String
    let depth: Int
    let agentRole: String
    let parentId: String?
    let turns: [AnalyticsSessionTurnRecord]

    var id: String { sessionId }
    var totalTokens: Int { turns.reduce(0) { $0 + $1.totalTokens } }
    var lastActivity: Date { turns.map(\.timestamp).max() ?? .distantPast }
}

enum AnalyticsDataConfidence: String, Codable, Equatable, Sendable {
    case high
    case degraded
    case low
}

struct AnalyticsSummary: Equatable, Sendable {
    let totalTokens: Int
    let estimatedTotalCost: Double
    let busiestAccountName: String?
    let busiestAccountTokens: Int
    let mostExpensiveProjectName: String?
    let mostExpensiveProjectCost: Double
    let activeAlertCount: Int
}

struct AnalyticsTrendPoint: Identifiable, Equatable, Sendable {
    let start: Date
    let tokens: Int
    let cost: Double

    var id: TimeInterval { start.timeIntervalSince1970 }
}

struct RateLimitAuditSample: Equatable, Sendable {
    let timestamp: Date
    let weeklyRemainingPercent: Int?
    let fiveHourRemainingPercent: Int?
    let limitReached: Bool
}

struct AnalyticsBreakdownItem: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let tokens: Int
    let cost: Double
    let shareOfTokens: Double
    let shareOfCost: Double
    let sessionCount: Int
}

struct AnalyticsLimitPressure: Identifiable, Equatable, Sendable {
    let profileId: UUID
    let profileName: String
    let riskLevel: RiskLevel
    let weeklyRemainingPercent: Int?
    let fiveHourRemainingPercent: Int?
    let estimatedTimeToExhaustion: Date?
    let staleReason: RateLimitStaleReason?
    let failureSummary: String?
    let confidence: AnalyticsDataConfidence

    var id: UUID { profileId }
}

enum AnalyticsUsageAuditStatus: String, Codable, Equatable, Sendable {
    case explained
    case weakAttribution
    case unattributed
}

struct AnalyticsUsageAuditEntry: Identifiable, Equatable, Sendable {
    let profileId: UUID
    let profileName: String
    let windowStart: Date
    let windowEnd: Date
    let weeklyDropPercent: Int
    let fiveHourDropPercent: Int
    let localTokens: Int
    let localSessionCount: Int
    let idleWindow: Bool
    let status: AnalyticsUsageAuditStatus

    var id: String {
        "\(profileId.uuidString)-\(windowEnd.timeIntervalSince1970)"
    }
}

struct AnalyticsUsageAuditPoint: Identifiable, Equatable, Sendable {
    let timestamp: Date
    let weeklyDropPercent: Int
    let fiveHourDropPercent: Int
    let localTokens: Int
    let idleWindow: Bool
    let status: AnalyticsUsageAuditStatus

    var id: TimeInterval { timestamp.timeIntervalSince1970 }
}

struct AnalyticsUsageAuditSummary: Equatable, Sendable {
    let explainedCount: Int
    let weakAttributionCount: Int
    let unattributedCount: Int
    let idleDrainCount: Int
    let totalDrainEvents: Int
    let latestEventAt: Date?

    static let empty = AnalyticsUsageAuditSummary(
        explainedCount: 0,
        weakAttributionCount: 0,
        unattributedCount: 0,
        idleDrainCount: 0,
        totalDrainEvents: 0,
        latestEventAt: nil
    )
}

enum AnalyticsAlertKind: String, Codable, Equatable, Sendable {
    case costSpike
    case acceleratedUsage
    case projectConcentration
    case limitPressure
    case staleData
    case unattributedDrain
}

enum AnalyticsAlertSeverity: String, Codable, Equatable, Sendable {
    case warning
    case critical
}

struct AnalyticsAlert: Identifiable, Equatable, Sendable {
    let kind: AnalyticsAlertKind
    let severity: AnalyticsAlertSeverity
    let title: String
    let message: String

    var id: String { "\(kind.rawValue)-\(severity.rawValue)-\(title)" }
}

struct AnalyticsDataQuality: Equatable, Sendable {
    let confidence: AnalyticsDataConfidence
    let staleProfileIds: [UUID]
    let lastSuccessfulFetch: Date?
    let message: String?
}

struct AnalyticsSnapshot: Equatable, Sendable {
    let generatedAt: Date
    let range: AnalyticsTimeRange
    let summary: AnalyticsSummary
    let tokenTrend: [AnalyticsTrendPoint]
    let costTrend: [AnalyticsTrendPoint]
    let dailyUsageByProfile: [UUID: [DailyUsage]]
    let accountBreakdown: [AnalyticsBreakdownItem]
    let projectBreakdown: [AnalyticsBreakdownItem]
    let modelBreakdown: [AnalyticsBreakdownItem]
    let projects: [ProjectUsage]
    let sessions: [SessionSummary]
    let hourlyActivity: [HourlyActivity]
    let expensiveTurns: [ExpensiveTurn]
    let limitPressure: [AnalyticsLimitPressure]
    let usageAuditSummary: AnalyticsUsageAuditSummary
    let usageAuditEntries: [AnalyticsUsageAuditEntry]
    let usageAuditTimeline: [AnalyticsUsageAuditPoint]
    let alerts: [AnalyticsAlert]
    let dataQuality: AnalyticsDataQuality

    static func empty(for range: AnalyticsTimeRange, generatedAt: Date = Date()) -> AnalyticsSnapshot {
        AnalyticsSnapshot(
            generatedAt: generatedAt,
            range: range,
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
            alerts: [],
            dataQuality: AnalyticsDataQuality(
                confidence: .high,
                staleProfileIds: [],
                lastSuccessfulFetch: nil,
                message: nil
            )
        )
    }
}
