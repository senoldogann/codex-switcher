import Foundation

struct SwitchReadinessEvaluator {
    private let policy: SwitchDecisionPolicy

    init(policy: SwitchDecisionPolicy) {
        self.policy = policy
    }

    func evaluate(
        profiles: [Profile],
        activeProfileId: UUID?,
        rateLimits: [UUID: RateLimitInfo],
        staleProfileIds: Set<UUID>
    ) -> SwitchReadinessEvaluation {
        let candidates = profiles.map { profile in
            readiness(
                profile: profile,
                activeProfileId: activeProfileId,
                rateLimit: rateLimits[profile.id],
                isStale: staleProfileIds.contains(profile.id)
            )
        }

        let preferredCandidateId = candidates
            .filter { $0.status == .ready || $0.status == .warning }
            .sorted(by: compareReadiness)
            .first?.profileId

        return SwitchReadinessEvaluation(
            candidates: candidates.sorted(by: compareReadiness),
            preferredCandidateId: preferredCandidateId
        )
    }

    private func readiness(
        profile: Profile,
        activeProfileId: UUID?,
        rateLimit: RateLimitInfo?,
        isStale: Bool
    ) -> SwitchCandidateReadiness {
        if profile.id == activeProfileId {
            return SwitchCandidateReadiness(
                profileId: profile.id,
                profileName: profile.displayName,
                status: .current,
                score: Int.min,
                reasons: [.activeProfile]
            )
        }

        var score = 1_000
        var reasons: [SwitchReadinessReason] = []
        var status: SwitchReadinessStatus = .ready

        if isStale {
            status = .warning
            score -= 250
            reasons.append(.staleAuth)
        }

        if let rateLimit {
            if rateLimit.limitReached {
                status = .blocked
                score = Int.min / 2
                reasons.append(.limitReached)
            }
            if let fiveHourRemaining = rateLimit.fiveHourRemainingPercent,
               fiveHourRemaining <= policy.fiveHourRemainingTriggerPercent {
                status = .blocked
                score = Int.min / 2
                reasons.append(.fiveHourPressure)
            }
            if let weeklyRemaining = rateLimit.weeklyRemainingPercent,
               weeklyRemaining <= policy.weeklyRemainingTriggerPercent {
                status = .blocked
                score = Int.min / 2
                reasons.append(.weeklyPressure)
            }
            score -= rateLimit.weeklyUsedPercent ?? 0
            score += rateLimit.fiveHourRemainingPercent ?? 0
        } else {
            if status != .blocked {
                status = .warning
            }
            score -= 120
            reasons.append(.missingRateLimit)
        }

        return SwitchCandidateReadiness(
            profileId: profile.id,
            profileName: profile.displayName,
            status: status,
            score: score,
            reasons: reasons
        )
    }

    private func compareReadiness(lhs: SwitchCandidateReadiness, rhs: SwitchCandidateReadiness) -> Bool {
        if rank(lhs.status) == rank(rhs.status) {
            if lhs.score == rhs.score {
                return lhs.profileName.localizedCaseInsensitiveCompare(rhs.profileName) == .orderedAscending
            }
            return lhs.score > rhs.score
        }
        return rank(lhs.status) > rank(rhs.status)
    }

    private func rank(_ status: SwitchReadinessStatus) -> Int {
        switch status {
        case .ready: return 4
        case .warning: return 3
        case .blocked: return 2
        case .current: return 1
        }
    }
}
