import Foundation

enum AutomaticSwitchReasonKind: Equatable {
    case limitReached
    case weeklyPressure
    case fiveHourPressure
}

struct SwitchDecisionPolicy {
    let weeklyRemainingTriggerPercent: Int
    let fiveHourRemainingTriggerPercent: Int

    init(
        weeklyRemainingTriggerPercent: Int = 5,
        fiveHourRemainingTriggerPercent: Int = 7
    ) {
        self.weeklyRemainingTriggerPercent = weeklyRemainingTriggerPercent
        self.fiveHourRemainingTriggerPercent = fiveHourRemainingTriggerPercent
    }

    func shouldLeaveCurrentProfile(_ rateLimit: RateLimitInfo?) -> Bool {
        guard let rateLimit else { return false }
        if rateLimit.limitReached { return true }
        if let fiveHourRemaining = rateLimit.fiveHourRemainingPercent,
           fiveHourRemaining <= fiveHourRemainingTriggerPercent {
            return true
        }
        if let weeklyRemaining = rateLimit.weeklyRemainingPercent,
           weeklyRemaining <= weeklyRemainingTriggerPercent {
            return true
        }
        return false
    }

    func isEligibleCandidate(_ rateLimit: RateLimitInfo?) -> Bool {
        guard let rateLimit else { return true }
        return !shouldLeaveCurrentProfile(rateLimit)
    }

    func nextAutomaticCandidate(
        profiles: [Profile],
        activeProfileId: UUID?,
        rateLimits: [UUID: RateLimitInfo]
    ) -> Profile? {
        let candidates = profiles.filter { $0.id != activeProfileId }
        let available = candidates.filter { isEligibleCandidate(rateLimits[$0.id]) }
        guard !available.isEmpty else { return nil }

        return available.min {
            (rateLimits[$0.id]?.weeklyUsedPercent ?? 0) < (rateLimits[$1.id]?.weeklyUsedPercent ?? 0)
        }
    }

    func automaticReasonKind(for rateLimit: RateLimitInfo?) -> AutomaticSwitchReasonKind? {
        guard let rateLimit else { return nil }
        if rateLimit.limitReached { return .limitReached }
        if let fiveHourRemaining = rateLimit.fiveHourRemainingPercent,
           fiveHourRemaining <= fiveHourRemainingTriggerPercent {
            return .fiveHourPressure
        }
        if let weeklyRemaining = rateLimit.weeklyRemainingPercent,
           weeklyRemaining <= weeklyRemainingTriggerPercent {
            return .weeklyPressure
        }
        return nil
    }
}
