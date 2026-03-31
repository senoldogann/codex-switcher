import Foundation

/// Risk level for rate limit exhaustion
enum RiskLevel: Equatable {
    case safe          // > 50% remaining
    case moderate      // 25-50% remaining
    case high          // 10-25% remaining
    case critical      // < 10% remaining
    case exhausted     // 0% / limit reached

    var color: String {
        switch self {
        case .safe: return "green"
        case .moderate: return "yellow"
        case .high: return "orange"
        case .critical: return "red"
        case .exhausted: return "red"
        }
    }

    var label: String {
        switch self {
        case .safe: return "Safe"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .critical: return "Critical"
        case .exhausted: return "Exhausted"
        }
    }
}

/// Rate limit risk forecasting based on usage pace
struct RateLimitForecast {
    let riskLevel: RiskLevel
    let estimatedTimeToExhaustion: Date?  // nil if safe or no pace data
    let pacePerHour: Double?              // tokens/hour

    init(riskLevel: RiskLevel, estimatedTimeToExhaustion: Date? = nil, pacePerHour: Double? = nil) {
        self.riskLevel = riskLevel
        self.estimatedTimeToExhaustion = estimatedTimeToExhaustion
        self.pacePerHour = pacePerHour
    }

    var timeToExhaustionLabel: String {
        guard let date = estimatedTimeToExhaustion else { return "" }
        let now = Date()
        guard date > now else { return "Now" }
        let minutes = Int(date.timeIntervalSince(now) / 60)
        if minutes < 60 { return "~\(minutes)m" }
        let hours = minutes / 60
        let mins = minutes % 60
        return "~\(hours)h \(mins)m"
    }
}

/// Forecasts rate limit risk based on current usage and session history
struct RateLimitForecaster {
    /// Compute risk forecast for a profile
    static func forecast(
        profileId: UUID,
        rateLimit: RateLimitInfo?,
        tokenUsage: AccountTokenUsage?,
        sessionHistory: [SessionPacePoint]
    ) -> RateLimitForecast {
        // If limit already reached
        if rateLimit?.limitReached == true {
            return RateLimitForecast(riskLevel: .exhausted)
        }

        // If no rate limit data, unknown
        guard let rl = rateLimit else {
            return RateLimitForecast(riskLevel: .safe)
        }

        // Determine remaining percentage (use 5-hour window as primary)
        let remainingPercent: Double
        if let fiveHour = rl.fiveHourRemainingPercent {
            remainingPercent = Double(fiveHour)
        } else if let weekly = rl.weeklyRemainingPercent {
            remainingPercent = Double(weekly)
        } else {
            return RateLimitForecast(riskLevel: .safe)
        }

        // Determine risk level from remaining %
        let riskLevel: RiskLevel
        if remainingPercent <= 0 {
            riskLevel = .exhausted
        } else if remainingPercent < 10 {
            riskLevel = .critical
        } else if remainingPercent < 25 {
            riskLevel = .high
        } else if remainingPercent < 50 {
            riskLevel = .moderate
        } else {
            riskLevel = .safe
        }

        // If we have pace data, estimate time to exhaustion
        guard let pace = computePace(from: sessionHistory), pace > 0 else {
            return RateLimitForecast(riskLevel: riskLevel)
        }

        // Estimate tokens remaining
        guard let usage = tokenUsage else {
            return RateLimitForecast(riskLevel: riskLevel, pacePerHour: pace)
        }

        // Estimate total token budget from remaining %
        let totalUsed = Double(usage.totalTokens)
        let remainingFraction = remainingPercent / 100.0
        guard remainingFraction < 1.0 else {
            return RateLimitForecast(riskLevel: riskLevel, pacePerHour: pace)
        }

        let totalBudget = totalUsed / (1.0 - remainingFraction)
        let tokensRemaining = totalBudget - totalUsed
        let hoursToExhaustion = tokensRemaining / pace
        let exhaustionDate = Date().addingTimeInterval(hoursToExhaustion * 3600)

        return RateLimitForecast(
            riskLevel: riskLevel,
            estimatedTimeToExhaustion: exhaustionDate,
            pacePerHour: pace
        )
    }

    /// Compute usage pace (tokens/hour) from session history
    private static func computePace(from history: [SessionPacePoint]) -> Double? {
        guard history.count >= 2 else { return nil }
        let sorted = history.sorted { $0.timestamp < $1.timestamp }
        let first = sorted.first!
        let last = sorted.last!
        let hours = last.timestamp.timeIntervalSince(first.timestamp) / 3600.0
        guard hours > 0 else { return nil }
        let tokens = Double(last.cumulativeTokens - first.cumulativeTokens)
        return tokens / hours
    }
}

/// A point in session usage history for pace calculation
struct SessionPacePoint: Equatable {
    let timestamp: Date
    let cumulativeTokens: Int
}
