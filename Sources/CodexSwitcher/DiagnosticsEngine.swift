import Foundation

struct DiagnosticsEngine: Sendable {
    private let maxEvents: Int

    init(maxEvents: Int = 40) {
        self.maxEvents = maxEvents
    }

    func makeTimeline(
        switchDecisions: [SwitchDecisionRecord],
        switchTimeline: [SwitchTimelineEvent],
        reconciliationEntries: [ReconciliationEntry],
        alerts: [AnalyticsAlert],
        dataQuality: AnalyticsDataQuality,
        generatedAt: Date
    ) -> [DiagnosticsEvent] {
        let decisionEvents = switchDecisions.map(makeDecisionEvent)
        let timelineEvents = switchTimeline.map(makeTimelineEvent)
        let reconciliationEvents = reconciliationEntries.compactMap(makeReconciliationEvent)
        let alertEvents = alerts.enumerated().map { index, alert in
            DiagnosticsEvent(
                id: "alert-\(index)-\(alert.id)",
                timestamp: generatedAt,
                kind: .alert,
                severity: alert.severity == .critical ? .critical : .warning,
                title: alert.title,
                detail: alert.message,
                subject: nil
            )
        }
        let dataQualityEvents = makeDataQualityEvents(dataQuality: dataQuality, generatedAt: generatedAt)

        return (decisionEvents + timelineEvents + reconciliationEvents + alertEvents + dataQualityEvents)
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.id > rhs.id
                }
                return lhs.timestamp > rhs.timestamp
            }
            .prefix(maxEvents)
            .map { $0 }
    }

    func makeSummary(events: [DiagnosticsEvent]) -> DiagnosticsSummary {
        DiagnosticsSummary(
            totalCount: events.count,
            warningCount: events.count { $0.severity == .warning },
            criticalCount: events.count { $0.severity == .critical },
            latestEventAt: events.first?.timestamp
        )
    }

    private func makeDecisionEvent(_ record: SwitchDecisionRecord) -> DiagnosticsEvent {
        DiagnosticsEvent(
            id: "decision-\(record.id.uuidString)",
            timestamp: record.timestamp,
            kind: .switchDecision,
            severity: severity(for: record.outcome),
            title: title(for: record.outcome),
            detail: record.detail,
            subject: record.chosenProfileName ?? record.requestedProfileName
        )
    }

    private func makeTimelineEvent(_ event: SwitchTimelineEvent) -> DiagnosticsEvent {
        DiagnosticsEvent(
            id: "timeline-\(event.id.uuidString)",
            timestamp: event.timestamp,
            kind: .switchTimeline,
            severity: severity(for: event.stage),
            title: title(for: event.stage),
            detail: event.detail,
            subject: event.targetProfileName
        )
    }

    private func makeReconciliationEvent(_ entry: ReconciliationEntry) -> DiagnosticsEvent? {
        guard entry.status == .unexplained || entry.status == .weakAttribution else { return nil }
        let severity: DiagnosticsEventSeverity = entry.status == .unexplained ? .critical : .warning
        return DiagnosticsEvent(
            id: "reconciliation-\(entry.id)",
            timestamp: entry.windowEnd,
            kind: .reconciliation,
            severity: severity,
            title: entry.status == .unexplained ? "Unexplained provider drain" : "Weak provider attribution",
            detail: "Weekly Δ \(entry.providerWeeklyDeltaPercent ?? 0)% · 5h Δ \(entry.providerFiveHourDeltaPercent ?? 0)% · local \(entry.localTokens) tokens.",
            subject: entry.profileName
        )
    }

    private func makeDataQualityEvents(
        dataQuality: AnalyticsDataQuality,
        generatedAt: Date
    ) -> [DiagnosticsEvent] {
        guard let message = dataQuality.message else { return [] }
        let severity: DiagnosticsEventSeverity
        switch dataQuality.confidence {
        case .high:
            severity = .info
        case .degraded:
            severity = .warning
        case .low:
            severity = .critical
        }
        return [
            DiagnosticsEvent(
                id: "data-quality-\(generatedAt.timeIntervalSince1970)",
                timestamp: generatedAt,
                kind: .dataQuality,
                severity: severity,
                title: "Data quality signal",
                detail: message,
                subject: nil
            )
        ]
    }

    private func severity(for outcome: SwitchDecisionOutcome) -> DiagnosticsEventSeverity {
        switch outcome {
        case .queued, .executed:
            return .info
        case .manualOverride, .blocked, .halted:
            return .warning
        }
    }

    private func severity(for stage: SwitchTimelineEvent.Stage) -> DiagnosticsEventSeverity {
        switch stage {
        case .queued, .ready, .verifying, .seamlessSuccess:
            return .info
        case .fallbackRestart, .inconclusive, .blocked, .halted:
            return .warning
        }
    }

    private func title(for outcome: SwitchDecisionOutcome) -> String {
        switch outcome {
        case .queued:
            return "Switch decision queued"
        case .executed:
            return "Switch decision executed"
        case .blocked:
            return "Switch decision blocked"
        case .halted:
            return "Switch automation halted"
        case .manualOverride:
            return "Manual override applied"
        }
    }

    private func title(for stage: SwitchTimelineEvent.Stage) -> String {
        switch stage {
        case .queued:
            return "Switch queued"
        case .ready:
            return "Switch ready"
        case .verifying:
            return "Switch verifying"
        case .seamlessSuccess:
            return "Seamless switch verified"
        case .fallbackRestart:
            return "Fallback restart applied"
        case .inconclusive:
            return "Switch outcome inconclusive"
        case .blocked:
            return "Switch blocked"
        case .halted:
            return "Switch halted"
        }
    }
}
