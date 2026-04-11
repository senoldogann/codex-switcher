import Foundation

// MARK: - Analytics & Token Refresh

extension AppStore {

    func refreshTokenUsage() {
        if isTokenRefreshRunning {
            shouldRefreshTokenUsageAfterCurrentRun = true
            return
        }
        isTokenRefreshRunning = true

        let profiles = self.profiles
        let history  = self.switchHistory
        let parser   = self.tokenParser
        let engine   = self.analyticsEngine
        let activeProfileId = self.activeProfile?.id
        let range    = self.analyticsTimeRange
        let rateLimits      = self.rateLimits
        let rateLimitHealth = self.rateLimitHealth
        let paceHistory     = self.paceHistory
        let auditSamples    = self.rateLimitAuditSamples
        let switchDecisionHistory = self.switchDecisionHistory
        let switchTimeline = self.switchTimeline
        let codexStateStore = self.codexStateStore

        DispatchQueue.global(qos: .utility).async {
            let result        = parser.calculate(profiles: profiles, history: history, activeProfileId: activeProfileId)
            let daily         = parser.calculateDaily(profiles: profiles, history: history, activeProfileId: activeProfileId, range: range)
            let records       = parser.calculateAnalyticsRecords(profiles: profiles, history: history, activeProfileId: activeProfileId)
            let sessionRecords = parser.calculateSessionRecords(range: range)
            let (newCosts, newForecasts) = AppStore.calculateCostsAndForecasts(
                profiles: profiles,
                tokenUsage: result,
                rateLimits: rateLimits,
                paceHistory: paceHistory
            )
            let workflowSummary = codexStateStore.loadWorkflowSummary(range: range, now: Date())
            let snapshot = engine.makeSnapshot(
                range: range,
                profiles: profiles,
                usageRecords: records,
                dailyUsageByProfile: daily,
                sessionRecords: sessionRecords,
                auditSamples: auditSamples,
                switchDecisionHistory: switchDecisionHistory,
                switchTimeline: switchTimeline,
                workflowSummary: workflowSummary,
                rateLimits: rateLimits,
                rateLimitHealth: rateLimitHealth,
                forecasts: newForecasts
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isTokenRefreshRunning = false
                let shouldRefreshAgain = self.shouldRefreshTokenUsageAfterCurrentRun
                self.shouldRefreshTokenUsageAfterCurrentRun = false

                if self.profiles.count == profiles.count {
                    self.tokenUsage       = result
                    self.analyticsSnapshot = snapshot
                    self.applyCostsAndForecasts(newCosts: newCosts, newForecasts: newForecasts)
                }

                if shouldRefreshAgain { self.refreshTokenUsage() }
            }
        }
    }

    func scheduleTokenRefresh() {
        tokenRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshTokenUsage() }
        tokenRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    nonisolated static func calculateCostsAndForecasts(
        profiles: [Profile],
        tokenUsage: [UUID: AccountTokenUsage],
        rateLimits: [UUID: RateLimitInfo],
        paceHistory: [SessionPacePoint]
    ) -> ([UUID: Double], [UUID: RateLimitForecast]) {
        let calculator = CostCalculator()
        var newCosts: [UUID: Double] = [:]
        var newForecasts: [UUID: RateLimitForecast] = [:]

        for profile in profiles {
            if let usage = tokenUsage[profile.id] {
                newCosts[profile.id] = calculator.cost(for: usage)
            }
            newForecasts[profile.id] = RateLimitForecaster.forecast(
                profileId: profile.id,
                rateLimit: rateLimits[profile.id],
                tokenUsage: tokenUsage[profile.id],
                sessionHistory: paceHistory
            )
        }
        return (newCosts, newForecasts)
    }

    func applyCostsAndForecasts(newCosts: [UUID: Double], newForecasts: [UUID: RateLimitForecast]) {
        costs     = newCosts
        forecasts = newForecasts
        refreshReliabilityAnalytics()

        checkBudget(costs: newCosts)
        checkWeeklySummary(costs: newCosts)

        let totalTokens = tokenUsage.values.reduce(0) { $0 + $1.totalTokens }
        if totalTokens > 0 {
            paceHistory.append(SessionPacePoint(timestamp: Date(), cumulativeTokens: totalTokens))
            let cutoff = Date().addingTimeInterval(-24 * 3600)
            paceHistory.removeAll { $0.timestamp < cutoff }
        }
    }

    // MARK: - Budget Alert

    private func checkBudget(costs: [UUID: Double]) {
        let limit = UserDefaults.standard.double(forKey: "weeklyBudgetUSD")
        let total = costs.values.reduce(0, +)
        let now   = Date()
        guard BudgetAlertPolicy.shouldAlert(
            totalCost: total,
            budgetLimit: limit,
            lastAlertDate: lastBudgetAlertDate,
            now: now
        ) else { return }
        lastBudgetAlertDate = now
        let spent = String(format: "%.2f", total)
        let cap   = String(format: "%.2f", limit)
        sendNotification(
            title: L("Bütçe aşıldı 💸", "Budget exceeded 💸"),
            body:  L("Bu hafta $\(spent) harcandı (limit: $\(cap))",
                     "Spent $\(spent) this week (budget: $\(cap))")
        )
    }

    // MARK: - Weekly Summary (Sunday evening)

    private func checkWeeklySummary(costs: [UUID: Double]) {
        let cal   = Calendar.current
        let now   = Date()
        let comps = cal.dateComponents([.weekday, .hour], from: now)
        guard comps.weekday == 1, (comps.hour ?? 0) >= 18 else { return }
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        if let last = lastWeeklySummaryDate, last > weekStart { return }
        lastWeeklySummaryDate = now

        let totalCost   = costs.values.reduce(0, +)
        let totalTokens = tokenUsage.values.reduce(0) { $0 + $1.totalTokens }
        let topProject  = analyticsSnapshot.summary.mostExpensiveProjectName ?? "—"

        func fmt(_ n: Int) -> String {
            n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000)
          : n >= 1_000     ? String(format: "%.1fK", Double(n) / 1_000)
          : "\(n)"
        }
        sendNotification(
            title: L("Haftalık Özet 📊", "Weekly Summary 📊"),
            body:  L("\(fmt(totalTokens)) token · $\(String(format:"%.2f",totalCost)) · \(topProject)",
                     "\(fmt(totalTokens)) tokens · $\(String(format:"%.2f",totalCost)) · top: \(topProject)")
        )
    }
}
