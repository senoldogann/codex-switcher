import Foundation

enum AutomationConfidenceCalculator {
    static func buildSummary(
        profiles: [Profile],
        staleProfileIds: Set<UUID>,
        rateLimitHealth: [UUID: RateLimitHealthStatus],
        reliability: SwitchReliabilitySnapshot,
        pendingSwitchRequest: PendingSwitchRequest?,
        switchTimeline: [SwitchTimelineEvent],
        now: Date
    ) -> AutomationConfidenceSummary {
        let staleProfileCount = profiles.filter { staleProfileIds.contains($0.id) }.count
        let stuckPendingAge = pendingSwitchRequest.map { max(0, Int(now.timeIntervalSince($0.queuedAt).rounded())) }
        let stuckPendingSwitch = (stuckPendingAge ?? 0) >= 90
        let lastVerifiedSwitchAt = switchTimeline
            .last(where: { $0.stage == .seamlessSuccess })?
            .timestamp

        if stuckPendingSwitch, let age = stuckPendingAge {
            return AutomationConfidenceSummary(
                status: .critical,
                highlight: "Pending switch has been stuck for \(age)s.",
                staleProfileCount: staleProfileCount,
                fallbackRestartCount: reliability.fallbackRestartCount,
                seamlessSuccessCount: reliability.seamlessSuccessCount,
                stuckPendingSwitch: true,
                lastVerifiedSwitchAt: lastVerifiedSwitchAt
            )
        }

        if staleProfileCount > 0 {
            return AutomationConfidenceSummary(
                status: .warning,
                highlight: "\(staleProfileCount) account needs re-login attention.",
                staleProfileCount: staleProfileCount,
                fallbackRestartCount: reliability.fallbackRestartCount,
                seamlessSuccessCount: reliability.seamlessSuccessCount,
                stuckPendingSwitch: false,
                lastVerifiedSwitchAt: lastVerifiedSwitchAt
            )
        }

        let recentFetchFailures = rateLimitHealth.values.filter {
            $0.failureSummary != nil && ($0.lastSuccessfulFetchAt == nil || ($0.lastFailedFetchAt ?? .distantPast) > ($0.lastSuccessfulFetchAt ?? .distantPast))
        }.count

        if reliability.fallbackRestartCount > reliability.seamlessSuccessCount && reliability.fallbackRestartCount > 0 {
            return AutomationConfidenceSummary(
                status: .warning,
                highlight: "Recent fallback restarts are outpacing seamless switch success.",
                staleProfileCount: staleProfileCount,
                fallbackRestartCount: reliability.fallbackRestartCount,
                seamlessSuccessCount: reliability.seamlessSuccessCount,
                stuckPendingSwitch: false,
                lastVerifiedSwitchAt: lastVerifiedSwitchAt
            )
        }

        if recentFetchFailures > 0 {
            return AutomationConfidenceSummary(
                status: .warning,
                highlight: "\(recentFetchFailures) account has fetch instability.",
                staleProfileCount: staleProfileCount,
                fallbackRestartCount: reliability.fallbackRestartCount,
                seamlessSuccessCount: reliability.seamlessSuccessCount,
                stuckPendingSwitch: false,
                lastVerifiedSwitchAt: lastVerifiedSwitchAt
            )
        }

        return AutomationConfidenceSummary(
            status: .healthy,
            highlight: "Automation looks healthy and recent seamless switches are holding.",
            staleProfileCount: staleProfileCount,
            fallbackRestartCount: reliability.fallbackRestartCount,
            seamlessSuccessCount: reliability.seamlessSuccessCount,
            stuckPendingSwitch: false,
            lastVerifiedSwitchAt: lastVerifiedSwitchAt
        )
    }

    static func buildAccountSummaries(
        profiles: [Profile],
        staleProfileIds: Set<UUID>,
        rateLimitHealth: [UUID: RateLimitHealthStatus],
        forecasts: [UUID: RateLimitForecast],
        costs: [UUID: Double],
        now: Date
    ) -> [AccountReliabilitySummary] {
        profiles.map { profile in
            let health = rateLimitHealth[profile.id]
            let forecast = forecasts[profile.id]
            let cost = costs[profile.id]

            if staleProfileIds.contains(profile.id) {
                let detail = health?.failureSummary ?? health?.staleReason?.summary ?? "stale auth"
                return AccountReliabilitySummary(
                    profileId: profile.id,
                    profileName: profile.displayName,
                    status: .critical,
                    detail: detail,
                    lastCheckedAt: health?.lastCheckedAt,
                    cost: cost,
                    riskLabel: forecast?.riskLevel.label
                )
            }

            if let health,
               let failureSummary = health.failureSummary,
               (health.lastSuccessfulFetchAt == nil || (health.lastFailedFetchAt ?? .distantPast) > (health.lastSuccessfulFetchAt ?? .distantPast)) {
                return AccountReliabilitySummary(
                    profileId: profile.id,
                    profileName: profile.displayName,
                    status: .warning,
                    detail: failureSummary,
                    lastCheckedAt: health.lastCheckedAt,
                    cost: cost,
                    riskLabel: forecast?.riskLevel.label
                )
            }

            if let forecast, forecast.riskLevel == .critical || forecast.riskLevel == .exhausted || forecast.riskLevel == .high {
                return AccountReliabilitySummary(
                    profileId: profile.id,
                    profileName: profile.displayName,
                    status: .warning,
                    detail: "limit risk \(forecast.riskLevel.label.lowercased())",
                    lastCheckedAt: health?.lastCheckedAt,
                    cost: cost,
                    riskLabel: forecast.riskLevel.label
                )
            }

            return AccountReliabilitySummary(
                profileId: profile.id,
                profileName: profile.displayName,
                status: .healthy,
                detail: "rate limits and auth look healthy",
                lastCheckedAt: health?.lastCheckedAt,
                cost: cost,
                riskLabel: forecast?.riskLevel.label
            )
        }
        .sorted { lhs, rhs in
            rank(lhs.status) > rank(rhs.status)
        }
    }

    private static func rank(_ status: AccountReliabilityStatus) -> Int {
        switch status {
        case .critical: return 3
        case .warning: return 2
        case .healthy: return 1
        }
    }
}
