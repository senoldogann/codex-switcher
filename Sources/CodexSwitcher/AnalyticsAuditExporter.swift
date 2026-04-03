import Foundation

enum AnalyticsAuditExporter {
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

    init(snapshot: AnalyticsSnapshot) {
        generatedAt = snapshot.generatedAt
        range = snapshot.range.rawValue
        usageAuditSummary = AnalyticsUsageAuditSummaryPayload(summary: snapshot.usageAuditSummary)
        usageAuditEntries = snapshot.usageAuditEntries.map(AnalyticsUsageAuditEntryPayload.init)
        usageAuditTimeline = snapshot.usageAuditTimeline.map(AnalyticsUsageAuditPointPayload.init)
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
