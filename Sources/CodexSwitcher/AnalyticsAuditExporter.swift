import Foundation

enum AnalyticsAuditExporter {
    static func buildCSV(for entries: [ReconciliationEntry]) -> String {
        let formatter = ISO8601DateFormatter()
        let rows = entries.map { entry in
            [
                escaped(entry.profileName),
                escaped(entry.status.rawValue),
                escaped(entry.reasonCode.rawValue),
                escaped(entry.confidence.rawValue),
                String(entry.providerWeeklyDeltaPercent.map(String.init) ?? ""),
                String(entry.providerFiveHourDeltaPercent.map(String.init) ?? ""),
                String(entry.localTokens),
                escaped(entry.matchedSessionIds.joined(separator: " ")),
                escaped(formatter.string(from: entry.windowStart)),
                escaped(formatter.string(from: entry.windowEnd))
            ].joined(separator: ",")
        }

        return ([
            "Profile,Status,Reason,Confidence,Weekly Delta %,5-Hour Delta %,Local Tokens,Matched Sessions,Window Start,Window End"
        ] + rows).joined(separator: "\n") + "\n"
    }

    static func buildCSV(for entries: [AnalyticsUsageAuditEntry]) -> String {
        let formatter = ISO8601DateFormatter()
        let rows = entries.map { entry in
            [
                escaped(entry.profileName),
                escaped(entry.status.rawValue),
                String(entry.idleWindow),
                String(entry.weeklyDropPercent),
                String(entry.fiveHourDropPercent),
                String(entry.localTokens),
                String(entry.localSessionCount),
                escaped(formatter.string(from: entry.windowStart)),
                escaped(formatter.string(from: entry.windowEnd))
            ].joined(separator: ",")
        }

        return ([
            "Profile,Status,Idle Window,Weekly Drop %,5-Hour Drop %,Local Tokens,Local Sessions,Window Start,Window End"
        ] + rows).joined(separator: "\n") + "\n"
    }

    static func buildJSON(for snapshot: AnalyticsSnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payload = AnalyticsAuditPayload(snapshot: snapshot)
        let data = try encoder.encode(payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return string
    }

    private static func escaped(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private struct AnalyticsAuditPayload: Encodable {
    let generatedAt: Date
    let range: String
    let usageAuditSummary: AnalyticsUsageAuditSummaryPayload
    let usageAuditEntries: [AnalyticsUsageAuditEntryPayload]
    let usageAuditTimeline: [AnalyticsUsageAuditPointPayload]
    let reconciliationSummary: ReconciliationSummaryPayload
    let reconciliationEntries: [ReconciliationEntryPayload]
    let reconciliationPolicy: ReconciliationPolicyPayload
    let diagnosticsSummary: DiagnosticsSummaryPayload
    let diagnosticsTimeline: [DiagnosticsEventPayload]

    init(snapshot: AnalyticsSnapshot) {
        generatedAt = snapshot.generatedAt
        range = snapshot.range.rawValue
        usageAuditSummary = AnalyticsUsageAuditSummaryPayload(summary: snapshot.usageAuditSummary)
        usageAuditEntries = snapshot.usageAuditEntries.map(AnalyticsUsageAuditEntryPayload.init)
        usageAuditTimeline = snapshot.usageAuditTimeline.map(AnalyticsUsageAuditPointPayload.init)
        reconciliationSummary = ReconciliationSummaryPayload(summary: snapshot.reconciliationSummary)
        reconciliationEntries = snapshot.reconciliationEntries.map(ReconciliationEntryPayload.init)
        reconciliationPolicy = ReconciliationPolicyPayload(policy: snapshot.reconciliationPolicy)
        diagnosticsSummary = DiagnosticsSummaryPayload(summary: snapshot.diagnosticsSummary)
        diagnosticsTimeline = snapshot.diagnosticsTimeline.map(DiagnosticsEventPayload.init)
    }
}

private struct AnalyticsUsageAuditSummaryPayload: Encodable {
    let explainedCount: Int
    let weakAttributionCount: Int
    let unattributedCount: Int
    let idleDrainCount: Int
    let totalDrainEvents: Int
    let latestEventAt: Date?

    init(summary: AnalyticsUsageAuditSummary) {
        explainedCount = summary.explainedCount
        weakAttributionCount = summary.weakAttributionCount
        unattributedCount = summary.unattributedCount
        idleDrainCount = summary.idleDrainCount
        totalDrainEvents = summary.totalDrainEvents
        latestEventAt = summary.latestEventAt
    }
}

private struct AnalyticsUsageAuditEntryPayload: Encodable {
    let profileId: UUID
    let profileName: String
    let windowStart: Date
    let windowEnd: Date
    let weeklyDropPercent: Int
    let fiveHourDropPercent: Int
    let localTokens: Int
    let localSessionCount: Int
    let idleWindow: Bool
    let status: String

    init(entry: AnalyticsUsageAuditEntry) {
        profileId = entry.profileId
        profileName = entry.profileName
        windowStart = entry.windowStart
        windowEnd = entry.windowEnd
        weeklyDropPercent = entry.weeklyDropPercent
        fiveHourDropPercent = entry.fiveHourDropPercent
        localTokens = entry.localTokens
        localSessionCount = entry.localSessionCount
        idleWindow = entry.idleWindow
        status = entry.status.rawValue
    }
}

private struct AnalyticsUsageAuditPointPayload: Encodable {
    let timestamp: Date
    let weeklyDropPercent: Int
    let fiveHourDropPercent: Int
    let localTokens: Int
    let idleWindow: Bool
    let status: String

    init(point: AnalyticsUsageAuditPoint) {
        timestamp = point.timestamp
        weeklyDropPercent = point.weeklyDropPercent
        fiveHourDropPercent = point.fiveHourDropPercent
        localTokens = point.localTokens
        idleWindow = point.idleWindow
        status = point.status.rawValue
    }
}

private struct ReconciliationSummaryPayload: Encodable {
    let explainedCount: Int
    let weakAttributionCount: Int
    let unexplainedCount: Int
    let ignoredCount: Int
    let idleDrainCount: Int
    let totalWindowCount: Int
    let totalProviderWeeklyDeltaPercent: Int
    let totalProviderFiveHourDeltaPercent: Int
    let totalLocalTokens: Int
    let latestWindowEnd: Date?

    init(summary: ReconciliationSummary) {
        explainedCount = summary.explainedCount
        weakAttributionCount = summary.weakAttributionCount
        unexplainedCount = summary.unexplainedCount
        ignoredCount = summary.ignoredCount
        idleDrainCount = summary.idleDrainCount
        totalWindowCount = summary.totalWindowCount
        totalProviderWeeklyDeltaPercent = summary.totalProviderWeeklyDeltaPercent
        totalProviderFiveHourDeltaPercent = summary.totalProviderFiveHourDeltaPercent
        totalLocalTokens = summary.totalLocalTokens
        latestWindowEnd = summary.latestWindowEnd
    }
}

private struct ReconciliationEntryPayload: Encodable {
    let profileId: UUID
    let profileName: String
    let windowStart: Date
    let windowEnd: Date
    let providerWeeklyDeltaPercent: Int?
    let providerFiveHourDeltaPercent: Int?
    let localTokens: Int
    let matchedSessionIds: [String]
    let status: String
    let reasonCode: String
    let confidence: String

    init(entry: ReconciliationEntry) {
        profileId = entry.profileId
        profileName = entry.profileName
        windowStart = entry.windowStart
        windowEnd = entry.windowEnd
        providerWeeklyDeltaPercent = entry.providerWeeklyDeltaPercent
        providerFiveHourDeltaPercent = entry.providerFiveHourDeltaPercent
        localTokens = entry.localTokens
        matchedSessionIds = entry.matchedSessionIds
        status = entry.status.rawValue
        reasonCode = entry.reasonCode.rawValue
        confidence = entry.confidence.rawValue
    }
}

private struct ReconciliationPolicyPayload: Encodable {
    let skewToleranceSeconds: Int
    let minDrainPercent: Int
    let minFiveHourDrainPercent: Int
    let lowLocalTokenThreshold: Int

    init(policy: ReconciliationPolicy) {
        skewToleranceSeconds = policy.skewToleranceSeconds
        minDrainPercent = policy.minDrainPercent
        minFiveHourDrainPercent = policy.minFiveHourDrainPercent
        lowLocalTokenThreshold = policy.lowLocalTokenThreshold
    }
}

private struct DiagnosticsSummaryPayload: Encodable {
    let totalCount: Int
    let warningCount: Int
    let criticalCount: Int
    let latestEventAt: Date?

    init(summary: DiagnosticsSummary) {
        totalCount = summary.totalCount
        warningCount = summary.warningCount
        criticalCount = summary.criticalCount
        latestEventAt = summary.latestEventAt
    }
}

private struct DiagnosticsEventPayload: Encodable {
    let timestamp: Date
    let kind: String
    let severity: String
    let title: String
    let detail: String
    let subject: String?

    init(event: DiagnosticsEvent) {
        timestamp = event.timestamp
        kind = event.kind.rawValue
        severity = event.severity.rawValue
        title = event.title
        detail = event.detail
        subject = event.subject
    }
}
