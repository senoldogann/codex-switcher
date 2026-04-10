import Foundation

enum SwitchDecisionSource: String, Codable, Equatable {
    case automatic
    case manual
}

enum SwitchDecisionOutcome: String, Codable, Equatable {
    case queued
    case executed
    case blocked
    case halted
    case manualOverride
}

enum SwitchReadinessStatus: String, Codable, Equatable {
    case current
    case ready
    case warning
    case blocked
}

enum SwitchReadinessReason: String, Codable, Equatable {
    case activeProfile
    case staleAuth
    case missingRateLimit
    case limitReached
    case weeklyPressure
    case fiveHourPressure
}

struct SwitchCandidateReadiness: Codable, Equatable, Identifiable {
    var id: UUID { profileId }

    let profileId: UUID
    let profileName: String
    let status: SwitchReadinessStatus
    let score: Int
    let reasons: [SwitchReadinessReason]
}

struct SwitchReadinessEvaluation: Equatable {
    let candidates: [SwitchCandidateReadiness]
    let preferredCandidateId: UUID?
}

struct SwitchDecisionRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let source: SwitchDecisionSource
    let outcome: SwitchDecisionOutcome
    let requestedProfileId: UUID?
    let requestedProfileName: String?
    let chosenProfileId: UUID?
    let chosenProfileName: String?
    let reason: String
    let detail: String
    let overrideApplied: Bool
    let readiness: [SwitchCandidateReadiness]
}
