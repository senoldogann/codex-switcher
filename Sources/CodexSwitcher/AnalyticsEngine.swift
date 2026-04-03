import Foundation

struct AnalyticsEngine: Sendable {
    private typealias DerivedInsights = (
        projects: [ProjectUsage],
        sessions: [SessionSummary],
        hourlyActivity: [HourlyActivity],
        expensiveTurns: [ExpensiveTurn]
    )

    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let calculator = CostCalculator()

    init(now: @escaping @Sendable () -> Date = Date.init, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    func makeSnapshot(
        range: AnalyticsTimeRange,
        profiles: [Profile],
        usageRecords: [AnalyticsUsageRecord],
        dailyUsageByProfile: [UUID: [DailyUsage]] = [:],
        sessionRecords: [AnalyticsSessionRecord] = [],
        rateLimits: [UUID: RateLimitInfo],
        rateLimitHealth: [UUID: RateLimitHealthStatus],
        forecasts: [UUID: RateLimitForecast]
    ) -> AnalyticsSnapshot {
        let generatedAt = now()
        let filteredRecords = filter(records: usageRecords, range: range, now: generatedAt)
        let totalTokens = filteredRecords.reduce(0) { $0 + $1.totalTokens }
        let totalCost = filteredRecords.reduce(0) { $0 + calculator.cost(for: $1.usage) }

        let accountBreakdown = makeBreakdown(
            records: filteredRecords,
            totalTokens: totalTokens,
            totalCost: totalCost,
            key: { $0.profileId.uuidString },
            name: { record in
                profiles.first(where: { $0.id == record.profileId })?.displayName ?? L("Bilinmiyor", "Unknown")
            }
        )
        let projectBreakdown = makeBreakdown(
            records: filteredRecords,
            totalTokens: totalTokens,
            totalCost: totalCost,
            key: { $0.projectPath },
            name: { $0.projectName }
        )
        let modelBreakdown = makeBreakdown(
            records: filteredRecords,
            totalTokens: totalTokens,
            totalCost: totalCost,
            key: { $0.model },
            name: { $0.model }
        )

        let insights = buildInsights(sessionRecords: sessionRecords)
        let limitPressure = makeLimitPressure(
            profiles: profiles,
            rateLimits: rateLimits,
            rateLimitHealth: rateLimitHealth,
            forecasts: forecasts
        )
        let dataQuality = makeDataQuality(health: rateLimitHealth)
        let alerts = makeAlerts(
            filteredRecords: filteredRecords,
            totalCost: totalCost,
            projectBreakdown: projectBreakdown,
            limitPressure: limitPressure,
            dataQuality: dataQuality,
            now: generatedAt
        )
        let summary = AnalyticsSummary(
            totalTokens: totalTokens,
            estimatedTotalCost: totalCost,
            busiestAccountName: accountBreakdown.first?.name,
            busiestAccountTokens: accountBreakdown.first?.tokens ?? 0,
            mostExpensiveProjectName: projectBreakdown.first?.name,
            mostExpensiveProjectCost: projectBreakdown.first?.cost ?? 0,
            activeAlertCount: alerts.count
        )

        let trend = makeTrend(records: filteredRecords, range: range, now: generatedAt)

        return AnalyticsSnapshot(
            generatedAt: generatedAt,
            range: range,
            summary: summary,
            tokenTrend: trend,
            costTrend: trend,
            dailyUsageByProfile: dailyUsageByProfile,
            accountBreakdown: accountBreakdown,
            projectBreakdown: projectBreakdown,
            modelBreakdown: modelBreakdown,
            projects: insights.projects,
            sessions: insights.sessions,
            hourlyActivity: insights.hourlyActivity,
            expensiveTurns: insights.expensiveTurns,
            limitPressure: limitPressure,
            alerts: alerts,
            dataQuality: dataQuality
        )
    }

    private func buildInsights(sessionRecords: [AnalyticsSessionRecord]) -> DerivedInsights {
        guard !sessionRecords.isEmpty else { return ([], [], [], []) }

        let calendar = calendarForInsights
        var projectTokens: [String: Int] = [:]
        var projectCosts: [String: Double] = [:]
        var projectSessions: [String: Int] = [:]
        var projectLastUsed: [String: Date] = [:]
        var projectNames: [String: String] = [:]

        for session in sessionRecords {
            projectNames[session.projectPath] = session.projectName
            projectTokens[session.projectPath, default: 0] += session.totalTokens
            projectSessions[session.projectPath, default: 0] += 1
            if (projectLastUsed[session.projectPath] ?? .distantPast) < session.lastActivity {
                projectLastUsed[session.projectPath] = session.lastActivity
            }

            let usage = session.turns.reduce(AccountTokenUsage()) { partial, turn in
                partial + turn.usage
            }
            projectCosts[session.projectPath, default: 0] += calculator.cost(for: usage)
        }

        let projects = projectTokens.keys
            .map { path in
                ProjectUsage(
                    id: path,
                    name: projectNames[path] ?? path,
                    path: path,
                    tokens: projectTokens[path] ?? 0,
                    cost: projectCosts[path] ?? 0,
                    sessionCount: projectSessions[path] ?? 0,
                    lastUsed: projectLastUsed[path] ?? .distantPast
                )
            }
            .sorted { lhs, rhs in
                if lhs.tokens == rhs.tokens {
                    return lhs.cost > rhs.cost
                }
                return lhs.tokens > rhs.tokens
            }

        let sessions = sessionRecords
            .map { session in
                SessionSummary(
                    id: session.sessionId.isEmpty ? UUID().uuidString : session.sessionId,
                    projectName: session.projectName,
                    projectPath: session.projectPath,
                    firstPrompt: session.firstPrompt,
                    tokens: session.totalTokens,
                    timestamp: session.lastActivity,
                    depth: session.depth,
                    agentRole: session.agentRole,
                    parentId: session.parentId
                )
            }
            .sorted { $0.timestamp > $1.timestamp }

        var hourlyMap: [String: Int] = [:]
        for session in sessionRecords {
            for turn in session.turns {
                let components = calendar.dateComponents([.weekday, .hour], from: turn.timestamp)
                let raw = (components.weekday ?? 1) - 1
                let dow = raw == 0 ? 6 : raw - 1
                let hour = components.hour ?? 0
                let key = "\(dow)-\(hour)"
                hourlyMap[key, default: 0] += turn.totalTokens
            }
        }

        var hourlyActivity: [HourlyActivity] = []
        for dow in 0..<7 {
            for hour in 0..<24 {
                let key = "\(dow)-\(hour)"
                hourlyActivity.append(HourlyActivity(hour: hour, dayOfWeek: dow, tokens: hourlyMap[key] ?? 0))
            }
        }

        let allTurns = sessionRecords.flatMap { session in
            session.turns.map { turn in
                ExpensiveTurn(
                    id: "\(session.sessionId)-\(turn.timestamp.timeIntervalSince1970)",
                    projectName: session.projectName,
                    promptPreview: turn.promptPreview,
                    inputTokens: turn.inputTokens,
                    outputTokens: turn.outputTokens,
                    cost: calculator.cost(for: turn.usage),
                    timestamp: turn.timestamp,
                    model: turn.model
                )
            }
        }

        let expensiveTurns = Array(allTurns.sorted { $0.cost > $1.cost }.prefix(20))

        return (projects, sessions, hourlyActivity, expensiveTurns)
    }

    private var calendarForInsights: Calendar { calendar }

    private func filter(records: [AnalyticsUsageRecord], range: AnalyticsTimeRange, now: Date) -> [AnalyticsUsageRecord] {
        guard let cutoff = range.cutoffDate(from: now) else { return records.sorted { $0.timestamp < $1.timestamp } }
        return records
            .filter { $0.timestamp > cutoff }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func makeBreakdown(
        records: [AnalyticsUsageRecord],
        totalTokens: Int,
        totalCost: Double,
        key: (AnalyticsUsageRecord) -> String,
        name: (AnalyticsUsageRecord) -> String
    ) -> [AnalyticsBreakdownItem] {
        var grouped: [String: (name: String, tokens: Int, cost: Double, sessions: Set<String>)] = [:]

        for record in records {
            let id = key(record)
            let recordCost = calculator.cost(for: record.usage)
            var entry = grouped[id] ?? (name(record), 0, 0, [])
            entry.tokens += record.totalTokens
            entry.cost += recordCost
            entry.sessions.insert(record.sessionId)
            grouped[id] = entry
        }

        return grouped.map { id, entry in
            AnalyticsBreakdownItem(
                id: id,
                name: entry.name,
                tokens: entry.tokens,
                cost: entry.cost,
                shareOfTokens: totalTokens > 0 ? Double(entry.tokens) / Double(totalTokens) : 0,
                shareOfCost: totalCost > 0 ? entry.cost / totalCost : 0,
                sessionCount: entry.sessions.count
            )
        }
        .sorted {
            if $0.cost == $1.cost {
                return $0.tokens > $1.tokens
            }
            return $0.cost > $1.cost
        }
    }

    private func makeTrend(records: [AnalyticsUsageRecord], range: AnalyticsTimeRange, now: Date) -> [AnalyticsTrendPoint] {
        guard !records.isEmpty else { return [] }

        let bucketComponent: Calendar.Component = range == .twentyFourHours ? .hour : .day
        let start: Date = {
            if let cutoff = range.cutoffDate(from: now) {
                return bucketStart(for: cutoff, component: bucketComponent)
            }
            let earliest = records.map(\.timestamp).min() ?? now
            return bucketStart(for: earliest, component: bucketComponent)
        }()
        let end = bucketStart(for: now, component: bucketComponent)

        var grouped: [Date: (tokens: Int, cost: Double)] = [:]
        for record in records {
            let bucket = bucketStart(for: record.timestamp, component: bucketComponent)
            var entry = grouped[bucket] ?? (0, 0)
            entry.tokens += record.totalTokens
            entry.cost += calculator.cost(for: record.usage)
            grouped[bucket] = entry
        }

        var points: [AnalyticsTrendPoint] = []
        var cursor = start
        while cursor <= end {
            let value = grouped[cursor] ?? (0, 0)
            points.append(AnalyticsTrendPoint(start: cursor, tokens: value.tokens, cost: value.cost))
            guard let next = calendar.date(byAdding: bucketComponent, value: 1, to: cursor) else { break }
            cursor = next
        }

        return points
    }

    private func bucketStart(for date: Date, component: Calendar.Component) -> Date {
        switch component {
        case .hour:
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return calendar.date(from: components) ?? date
        default:
            return calendar.startOfDay(for: date)
        }
    }

    private func makeLimitPressure(
        profiles: [Profile],
        rateLimits: [UUID: RateLimitInfo],
        rateLimitHealth: [UUID: RateLimitHealthStatus],
        forecasts: [UUID: RateLimitForecast]
    ) -> [AnalyticsLimitPressure] {
        profiles.map { profile in
            let rateLimit = rateLimits[profile.id]
            let health = rateLimitHealth[profile.id]
            let forecast = forecasts[profile.id]
            let confidence: AnalyticsDataConfidence
            if health?.staleReason != nil || health?.failureSummary != nil {
                confidence = .low
            } else if let lastSuccessfulFetchAt = health?.lastSuccessfulFetchAt,
                      now().timeIntervalSince(lastSuccessfulFetchAt) > 12 * 3600 {
                confidence = .degraded
            } else {
                confidence = .high
            }

            return AnalyticsLimitPressure(
                profileId: profile.id,
                profileName: profile.displayName,
                riskLevel: forecast?.riskLevel ?? .safe,
                weeklyRemainingPercent: rateLimit?.weeklyRemainingPercent,
                fiveHourRemainingPercent: rateLimit?.fiveHourRemainingPercent,
                estimatedTimeToExhaustion: forecast?.estimatedTimeToExhaustion,
                staleReason: health?.staleReason,
                failureSummary: health?.failureSummary,
                confidence: confidence
            )
        }
        .sorted { lhs, rhs in
            let lhsScore = riskScore(lhs.riskLevel, confidence: lhs.confidence)
            let rhsScore = riskScore(rhs.riskLevel, confidence: rhs.confidence)
            if lhsScore == rhsScore {
                return lhs.profileName < rhs.profileName
            }
            return lhsScore > rhsScore
        }
    }

    private func riskScore(_ risk: RiskLevel, confidence: AnalyticsDataConfidence) -> Int {
        let base: Int = switch risk {
        case .exhausted: 50
        case .critical: 40
        case .high: 30
        case .moderate: 20
        case .safe: 10
        }
        let confidenceBoost: Int = switch confidence {
        case .low: 8
        case .degraded: 4
        case .high: 0
        }
        return base + confidenceBoost
    }

    private func makeDataQuality(health: [UUID: RateLimitHealthStatus]) -> AnalyticsDataQuality {
        let staleProfiles = health.compactMap { id, status in
            (status.staleReason != nil || status.failureSummary != nil) ? id : nil
        }
        let lastSuccessfulFetch = health.values.compactMap(\.lastSuccessfulFetchAt).max()

        let confidence: AnalyticsDataConfidence
        let message: String?
        if !staleProfiles.isEmpty {
            confidence = .low
            message = "Some rate-limit data is stale or failed to refresh."
        } else if let lastSuccessfulFetch,
                  now().timeIntervalSince(lastSuccessfulFetch) > 12 * 3600 {
            confidence = .degraded
            message = "Rate-limit data is aging; some cards may lag behind current usage."
        } else {
            confidence = .high
            message = nil
        }

        return AnalyticsDataQuality(
            confidence: confidence,
            staleProfileIds: staleProfiles.sorted { $0.uuidString < $1.uuidString },
            lastSuccessfulFetch: lastSuccessfulFetch,
            message: message
        )
    }

    private func makeAlerts(
        filteredRecords: [AnalyticsUsageRecord],
        totalCost: Double,
        projectBreakdown: [AnalyticsBreakdownItem],
        limitPressure: [AnalyticsLimitPressure],
        dataQuality: AnalyticsDataQuality,
        now: Date
    ) -> [AnalyticsAlert] {
        var alerts: [AnalyticsAlert] = []

        let last24hRecords = filteredRecords.filter { $0.timestamp > now.addingTimeInterval(-24 * 3600) }
        let priorWeekRecords = filteredRecords.filter {
            $0.timestamp <= now.addingTimeInterval(-24 * 3600) &&
            $0.timestamp > now.addingTimeInterval(-7 * 24 * 3600)
        }
        let previous24hRecords = filteredRecords.filter {
            $0.timestamp <= now.addingTimeInterval(-24 * 3600) &&
            $0.timestamp > now.addingTimeInterval(-48 * 3600)
        }

        let last24hCost = last24hRecords.reduce(0) { $0 + calculator.cost(for: $1.usage) }
        let baselineDailyAverage = priorWeekRecords.isEmpty
            ? 0
            : priorWeekRecords.reduce(0) { $0 + calculator.cost(for: $1.usage) } / 6.0

        if baselineDailyAverage > 0,
           last24hCost >= baselineDailyAverage * 2.5,
           last24hCost - baselineDailyAverage >= 0.5 {
            alerts.append(
                AnalyticsAlert(
                    kind: .costSpike,
                    severity: .critical,
                    title: "Cost spike detected",
                    message: "Last 24 hours are running at \(formatMultiple(last24hCost / baselineDailyAverage)) the recent daily baseline."
                )
            )
        }

        let last24hTokens = last24hRecords.reduce(0) { $0 + $1.totalTokens }
        let previous24hTokens = previous24hRecords.reduce(0) { $0 + $1.totalTokens }
        if previous24hTokens > 0,
           Double(last24hTokens) >= Double(previous24hTokens) * 1.8,
           last24hTokens - previous24hTokens >= 5_000 {
            alerts.append(
                AnalyticsAlert(
                    kind: .acceleratedUsage,
                    severity: .warning,
                    title: L("Kullanım hızlanıyor", "Usage is accelerating"),
                    message: L(
                        "Son 24 saatteki token tüketimi, önceki 24 saatlik pencerenin belirgin şekilde üstünde.",
                        "Token consumption in the last 24 hours is materially above the prior 24-hour window."
                    )
                )
            )
        }

        if let topProject = projectBreakdown.first,
           projectBreakdown.count > 1,
           totalCost >= 0.5,
           topProject.shareOfCost >= 0.65 {
            alerts.append(
                AnalyticsAlert(
                    kind: .projectConcentration,
                    severity: .warning,
                    title: L("Proje maliyeti yoğunlaşıyor", "Project spend is concentrated"),
                    message: L(
                        "\(topProject.name), bu aralıktaki izlenen maliyetin %\(Int((topProject.shareOfCost * 100).rounded())) kadarını oluşturuyor.",
                        "\(topProject.name) accounts for \(Int((topProject.shareOfCost * 100).rounded()))% of tracked cost in this range."
                    )
                )
            )
        }

        if let pressured = limitPressure.first(where: {
            $0.riskLevel == .critical || $0.riskLevel == .high || $0.riskLevel == .exhausted
        }) {
            let detail: String
            if let eta = pressured.estimatedTimeToExhaustion {
                detail = L(
                    "Tahmini tükenme zamanı \(eta.formatted(date: .omitted, time: .shortened)).",
                    "Projected exhaustion around \(eta.formatted(date: .omitted, time: .shortened))."
                )
            } else if let weeklyRemainingPercent = pressured.weeklyRemainingPercent {
                detail = L(
                    "Haftalık kalan kapasite %\(weeklyRemainingPercent).",
                    "Weekly remaining capacity is \(weeklyRemainingPercent)%."
                )
            } else if let fiveHourRemainingPercent = pressured.fiveHourRemainingPercent {
                detail = L(
                    "5 saatlik kalan kapasite %\(fiveHourRemainingPercent).",
                    "5-hour remaining capacity is \(fiveHourRemainingPercent)%."
                )
            } else {
                detail = L(
                    "Kalan kapasite kritik eşiğe doğru gidiyor.",
                    "Remaining capacity is trending toward a critical threshold."
                )
            }

            alerts.append(
                AnalyticsAlert(
                    kind: .limitPressure,
                    severity: pressured.riskLevel == .critical || pressured.riskLevel == .exhausted ? .critical : .warning,
                    title: L("Limit baskısı artıyor", "Limit pressure is rising"),
                    message: L(
                        "\(pressured.profileName) için baskı yükseliyor. \(detail)",
                        "\(pressured.profileName) shows elevated pressure. \(detail)"
                    )
                )
            )
        }

        if dataQuality.confidence != .high {
            alerts.append(
                AnalyticsAlert(
                    kind: .staleData,
                    severity: .warning,
                    title: L("Veri güveni azaldı", "Data confidence is reduced"),
                    message: dataQuality.message ?? L(
                        "Bazı kartlar stale rate-limit verisine dayanıyor.",
                        "Some cards are based on stale rate-limit data."
                    )
                )
            )
        }

        return alerts.sorted {
            if $0.severity == $1.severity {
                return $0.title < $1.title
            }
            return $0.severity == .critical && $1.severity != .critical
        }
    }

    private func formatMultiple(_ value: Double) -> String {
        String(format: "%.1fx", value)
    }
}
