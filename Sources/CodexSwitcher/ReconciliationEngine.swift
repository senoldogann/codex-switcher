import Foundation

struct ReconciliationEngine: Sendable {
    private struct Window: Sendable {
        let profileId: UUID
        let profileName: String
        let windowStart: Date
        let windowEnd: Date
        let weeklyDeltaPercent: Int?
        let fiveHourDeltaPercent: Int?
        let statusOverride: ReconciliationStatus?
        let reasonCodeOverride: ReconciliationReasonCode?
        let confidenceOverride: ReconciliationConfidence?
    }

    let policy: ReconciliationPolicy
    let now: @Sendable () -> Date

    init(
        policy: ReconciliationPolicy = ReconciliationPolicy(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.policy = policy
        self.now = now
    }

    func makeReport(
        range: AnalyticsTimeRange,
        profiles: [Profile],
        records: [AnalyticsUsageRecord],
        auditSamples: [UUID: [RateLimitAuditSample]]
    ) -> ReconciliationReport {
        let profileNames = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.displayName) })
        let cutoff = range.cutoffDate(from: now())
        let windows = auditSamples.flatMap { profileId, samples in
            makeWindows(
                profileId: profileId,
                profileName: profileNames[profileId] ?? L("Bilinmiyor", "Unknown"),
                samples: samples,
                cutoff: cutoff
            )
        }
        let assignments = assignRecords(records, to: windows)
        let entries = windows.enumerated()
            .map { index, window in
                makeEntry(window: window, matchedRecords: assignments[index] ?? [])
            }
            .sorted { lhs, rhs in
                if lhs.windowEnd == rhs.windowEnd {
                    return statusRank(lhs.status) > statusRank(rhs.status)
                }
                return lhs.windowEnd > rhs.windowEnd
            }

        return ReconciliationReport(
            summary: ReconciliationSummary(entries: entries),
            entries: entries
        )
    }

    private func makeWindows(
        profileId: UUID,
        profileName: String,
        samples: [RateLimitAuditSample],
        cutoff: Date?
    ) -> [Window] {
        let sortedSamples = samples.sorted { $0.timestamp < $1.timestamp }
        guard sortedSamples.count >= 2 else { return [] }

        return (1..<sortedSamples.count).compactMap { index in
            let previous = sortedSamples[index - 1]
            let current = sortedSamples[index]

            if let cutoff, current.timestamp <= cutoff {
                return nil
            }

            return makeWindow(
                profileId: profileId,
                profileName: profileName,
                previous: previous,
                current: current
            )
        }
    }

    private func makeWindow(
        profileId: UUID,
        profileName: String,
        previous: RateLimitAuditSample,
        current: RateLimitAuditSample
    ) -> Window {
        let weeklyDelta = makeDrop(
            previous: previous.weeklyRemainingPercent,
            current: current.weeklyRemainingPercent
        )
        let fiveHourDelta = makeDrop(
            previous: previous.fiveHourRemainingPercent,
            current: current.fiveHourRemainingPercent
        )
        let hasMissingSample = weeklyDelta == nil || fiveHourDelta == nil

        if hasMissingSample {
            return Window(
                profileId: profileId,
                profileName: profileName,
                windowStart: previous.timestamp,
                windowEnd: current.timestamp,
                weeklyDeltaPercent: weeklyDelta,
                fiveHourDeltaPercent: fiveHourDelta,
                statusOverride: .ignored,
                reasonCodeOverride: .missingProviderSample,
                confidenceOverride: .low
            )
        }

        if hasCounterJump(previous: previous, current: current) {
            return Window(
                profileId: profileId,
                profileName: profileName,
                windowStart: previous.timestamp,
                windowEnd: current.timestamp,
                weeklyDeltaPercent: nil,
                fiveHourDeltaPercent: nil,
                statusOverride: .ignored,
                reasonCodeOverride: .sampleResetOrCounterJump,
                confidenceOverride: .low
            )
        }

        if policy.isBelowNoiseFloor(
            weeklyDeltaPercent: weeklyDelta,
            fiveHourDeltaPercent: fiveHourDelta
        ), !(previous.limitReached == false && current.limitReached == true) {
            return Window(
                profileId: profileId,
                profileName: profileName,
                windowStart: previous.timestamp,
                windowEnd: current.timestamp,
                weeklyDeltaPercent: weeklyDelta,
                fiveHourDeltaPercent: fiveHourDelta,
                statusOverride: .ignored,
                reasonCodeOverride: .belowNoiseFloor,
                confidenceOverride: .high
            )
        }

        return Window(
            profileId: profileId,
            profileName: profileName,
            windowStart: previous.timestamp,
            windowEnd: current.timestamp,
            weeklyDeltaPercent: weeklyDelta,
            fiveHourDeltaPercent: fiveHourDelta,
            statusOverride: nil,
            reasonCodeOverride: nil,
            confidenceOverride: nil
        )
    }

    private func assignRecords(
        _ records: [AnalyticsUsageRecord],
        to windows: [Window]
    ) -> [Int: [AnalyticsUsageRecord]] {
        records
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.id < rhs.id
                }
                return lhs.timestamp < rhs.timestamp
            }
            .reduce(into: [Int: [AnalyticsUsageRecord]]()) { assignments, record in
                guard let windowIndex = nearestWindowIndex(for: record, windows: windows) else {
                    return
                }
                assignments[windowIndex, default: []].append(record)
            }
    }

    private func nearestWindowIndex(
        for record: AnalyticsUsageRecord,
        windows: [Window]
    ) -> Int? {
        windows.enumerated()
            .filter { _, window in
                window.profileId == record.profileId
                    && record.timestamp >= window.windowStart.addingTimeInterval(-Double(policy.skewToleranceSeconds))
                    && record.timestamp <= window.windowEnd.addingTimeInterval(Double(policy.skewToleranceSeconds))
            }
            .min { lhs, rhs in
                let lhsDistance = distance(from: record.timestamp, to: lhs.element)
                let rhsDistance = distance(from: record.timestamp, to: rhs.element)
                if lhsDistance == rhsDistance {
                    if lhs.element.windowEnd == rhs.element.windowEnd {
                        return lhs.offset < rhs.offset
                    }
                    return lhs.element.windowEnd < rhs.element.windowEnd
                }
                return lhsDistance < rhsDistance
            }?
            .offset
    }

    private func distance(from timestamp: Date, to window: Window) -> TimeInterval {
        if timestamp < window.windowStart {
            return window.windowStart.timeIntervalSince(timestamp)
        }
        if timestamp > window.windowEnd {
            return timestamp.timeIntervalSince(window.windowEnd)
        }
        return 0
    }

    private func makeEntry(
        window: Window,
        matchedRecords: [AnalyticsUsageRecord]
    ) -> ReconciliationEntry {
        let localTokens = matchedRecords.reduce(0) { $0 + $1.totalTokens }
        let matchedSessionIds = Array(Set(matchedRecords.map(\.sessionId))).sorted()

        let status = window.statusOverride ?? status(localTokens: localTokens, matchedSessionIds: matchedSessionIds)
        let reasonCode = window.reasonCodeOverride ?? reasonCode(
            status: status,
            matchedRecords: matchedRecords,
            window: window
        )
        let confidence = window.confidenceOverride ?? confidence(
            status: status,
            reasonCode: reasonCode
        )

        return ReconciliationEntry(
            profileId: window.profileId,
            profileName: window.profileName,
            windowStart: window.windowStart,
            windowEnd: window.windowEnd,
            providerWeeklyDeltaPercent: window.weeklyDeltaPercent,
            providerFiveHourDeltaPercent: window.fiveHourDeltaPercent,
            localTokens: localTokens,
            matchedSessionIds: matchedSessionIds,
            status: status,
            reasonCode: reasonCode,
            confidence: confidence
        )
    }

    private func status(
        localTokens: Int,
        matchedSessionIds: [String]
    ) -> ReconciliationStatus {
        if matchedSessionIds.isEmpty && localTokens == 0 {
            return .unexplained
        }
        if policy.hasLowLocalUsage(localTokens: localTokens) {
            return .weakAttribution
        }
        return .explained
    }

    private func reasonCode(
        status: ReconciliationStatus,
        matchedRecords: [AnalyticsUsageRecord],
        window: Window
    ) -> ReconciliationReasonCode {
        switch status {
        case .explained:
            return .matchedActivity
        case .weakAttribution:
            return hasBoundaryOverlap(matchedRecords: matchedRecords, window: window)
                ? .switchBoundaryOverlap
                : .lowLocalUsage
        case .unexplained:
            return .idleDrain
        case .ignored:
            return .belowNoiseFloor
        }
    }

    private func confidence(
        status: ReconciliationStatus,
        reasonCode: ReconciliationReasonCode
    ) -> ReconciliationConfidence {
        switch status {
        case .explained:
            return .high
        case .weakAttribution:
            return .medium
        case .unexplained, .ignored:
            return .low
        }
    }

    private func hasBoundaryOverlap(
        matchedRecords: [AnalyticsUsageRecord],
        window: Window
    ) -> Bool {
        matchedRecords.contains { record in
            min(
                abs(record.timestamp.timeIntervalSince(window.windowStart)),
                abs(record.timestamp.timeIntervalSince(window.windowEnd))
            ) <= Double(policy.skewToleranceSeconds)
        }
    }

    private func makeDrop(previous: Int?, current: Int?) -> Int? {
        guard let previous, let current else { return nil }
        return max(0, previous - current)
    }

    private func hasCounterJump(
        previous: RateLimitAuditSample,
        current: RateLimitAuditSample
    ) -> Bool {
        if let previousWeekly = previous.weeklyRemainingPercent,
           let currentWeekly = current.weeklyRemainingPercent,
           currentWeekly > previousWeekly {
            return true
        }
        if let previousFiveHour = previous.fiveHourRemainingPercent,
           let currentFiveHour = current.fiveHourRemainingPercent,
           currentFiveHour > previousFiveHour {
            return true
        }
        return previous.limitReached == true && current.limitReached == false
    }

    private func statusRank(_ status: ReconciliationStatus) -> Int {
        switch status {
        case .unexplained: return 4
        case .weakAttribution: return 3
        case .explained: return 2
        case .ignored: return 1
        }
    }
}
