import Foundation

enum ReconciliationStatus: String, Codable, Equatable, Sendable {
    case explained
    case weakAttribution
    case unexplained
    case ignored
}

enum ReconciliationReasonCode: String, Codable, Equatable, Sendable {
    case matchedActivity = "matched_activity"
    case lowLocalUsage = "low_local_usage"
    case idleDrain = "idle_drain"
    case missingProviderSample = "missing_provider_sample"
    case switchBoundaryOverlap = "switch_boundary_overlap"
    case belowNoiseFloor = "below_noise_floor"
    case sampleResetOrCounterJump = "sample_reset_or_counter_jump"
}

enum ReconciliationConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
}

struct ReconciliationEntry: Codable, Identifiable, Equatable, Sendable {
    let profileId: UUID
    let profileName: String
    let windowStart: Date
    let windowEnd: Date
    let providerWeeklyDeltaPercent: Int?
    let providerFiveHourDeltaPercent: Int?
    let localTokens: Int
    let matchedSessionIds: [String]
    let status: ReconciliationStatus
    let reasonCode: ReconciliationReasonCode
    let confidence: ReconciliationConfidence

    var id: String {
        "\(profileId.uuidString)-\(windowEnd.timeIntervalSince1970)-\(status.rawValue)-\(reasonCode.rawValue)"
    }

    init(
        profileId: UUID,
        profileName: String,
        windowStart: Date,
        windowEnd: Date,
        providerWeeklyDeltaPercent: Int?,
        providerFiveHourDeltaPercent: Int?,
        localTokens: Int,
        matchedSessionIds: [String],
        status: ReconciliationStatus,
        reasonCode: ReconciliationReasonCode,
        confidence: ReconciliationConfidence
    ) {
        self.profileId = profileId
        self.profileName = profileName
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.providerWeeklyDeltaPercent = providerWeeklyDeltaPercent
        self.providerFiveHourDeltaPercent = providerFiveHourDeltaPercent
        self.localTokens = localTokens
        self.matchedSessionIds = matchedSessionIds
        self.status = status
        self.reasonCode = reasonCode
        self.confidence = confidence
    }

    init(legacyAuditEntry: AnalyticsUsageAuditEntry) {
        self.init(
            profileId: legacyAuditEntry.profileId,
            profileName: legacyAuditEntry.profileName,
            windowStart: legacyAuditEntry.windowStart,
            windowEnd: legacyAuditEntry.windowEnd,
            providerWeeklyDeltaPercent: legacyAuditEntry.weeklyDropPercent,
            providerFiveHourDeltaPercent: legacyAuditEntry.fiveHourDropPercent,
            localTokens: legacyAuditEntry.localTokens,
            matchedSessionIds: [],
            status: ReconciliationStatus(legacyStatus: legacyAuditEntry.status),
            reasonCode: ReconciliationReasonCode(legacyAuditEntry: legacyAuditEntry),
            confidence: ReconciliationConfidence(legacyAuditEntry: legacyAuditEntry)
        )
    }
}

struct ReconciliationSummary: Codable, Equatable, Sendable {
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

    static let empty = ReconciliationSummary(entries: [])

    init(entries: [ReconciliationEntry]) {
        explainedCount = entries.count { $0.status == .explained }
        weakAttributionCount = entries.count { $0.status == .weakAttribution }
        unexplainedCount = entries.count { $0.status == .unexplained }
        ignoredCount = entries.count { $0.status == .ignored }
        idleDrainCount = entries.count { $0.reasonCode == .idleDrain }
        totalWindowCount = entries.count
        totalProviderWeeklyDeltaPercent = entries.reduce(0) {
            $0 + ($1.providerWeeklyDeltaPercent ?? 0)
        }
        totalProviderFiveHourDeltaPercent = entries.reduce(0) {
            $0 + ($1.providerFiveHourDeltaPercent ?? 0)
        }
        totalLocalTokens = entries.reduce(0) { $0 + $1.localTokens }
        latestWindowEnd = entries.map(\.windowEnd).max()
    }
}

struct ReconciliationReport: Codable, Equatable, Sendable {
    let summary: ReconciliationSummary
    let entries: [ReconciliationEntry]

    static let empty = ReconciliationReport(summary: .empty, entries: [])
}

struct ReconciliationPolicy: Codable, Equatable, Sendable {
    let skewToleranceSeconds: Int
    let minDrainPercent: Int
    let minFiveHourDrainPercent: Int
    let lowLocalTokenThreshold: Int

    init(
        skewToleranceSeconds: Int = 120,
        minDrainPercent: Int = 1,
        minFiveHourDrainPercent: Int = 1,
        lowLocalTokenThreshold: Int = 1_000
    ) {
        self.skewToleranceSeconds = skewToleranceSeconds
        self.minDrainPercent = minDrainPercent
        self.minFiveHourDrainPercent = minFiveHourDrainPercent
        self.lowLocalTokenThreshold = lowLocalTokenThreshold
    }

    func isBelowNoiseFloor(
        weeklyDeltaPercent: Int?,
        fiveHourDeltaPercent: Int?
    ) -> Bool {
        let weeklyBelowNoiseFloor = (weeklyDeltaPercent ?? 0) < minDrainPercent
        let fiveHourBelowNoiseFloor = (fiveHourDeltaPercent ?? 0) < minFiveHourDrainPercent
        return weeklyBelowNoiseFloor && fiveHourBelowNoiseFloor
    }

    func hasLowLocalUsage(localTokens: Int) -> Bool {
        localTokens < lowLocalTokenThreshold
    }
}

private extension ReconciliationStatus {
    init(legacyStatus: AnalyticsUsageAuditStatus) {
        switch legacyStatus {
        case .explained:
            self = .explained
        case .weakAttribution:
            self = .weakAttribution
        case .unattributed:
            self = .unexplained
        }
    }
}

private extension ReconciliationReasonCode {
    init(legacyAuditEntry: AnalyticsUsageAuditEntry) {
        switch legacyAuditEntry.status {
        case .explained:
            self = .matchedActivity
        case .weakAttribution:
            self = legacyAuditEntry.idleWindow ? .switchBoundaryOverlap : .lowLocalUsage
        case .unattributed:
            self = legacyAuditEntry.idleWindow ? .idleDrain : .lowLocalUsage
        }
    }
}

private extension ReconciliationConfidence {
    init(legacyAuditEntry: AnalyticsUsageAuditEntry) {
        switch legacyAuditEntry.status {
        case .explained:
            self = .high
        case .weakAttribution:
            self = .medium
        case .unattributed:
            self = .low
        }
    }
}
