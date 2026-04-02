import Foundation

struct Profile: Identifiable, Codable, Equatable {
    let id: UUID
    var alias: String
    var email: String
    var accountId: String
    var addedAt: Date
    var activatedAt: Date?       // Bu hesap en son ne zaman aktif edildi
    var lastKnownTurns: Int?     // Hesaptan çıkarken kaydedilen turn sayısı

    var displayName: String {
        alias.isEmpty ? email : alias
    }

    var shortEmail: String {
        let parts = email.components(separatedBy: "@")
        let local = parts.first ?? email
        return local.count > 14 ? String(local.prefix(14)) + "…" : local
    }

    var initial: String {
        String(displayName.prefix(1).uppercased())
    }
}

struct AppConfig: Codable {
    var profiles: [Profile]
    var activeProfileId: UUID?
    var roundRobinIndex: Int

    static let empty = AppConfig(profiles: [], activeProfileId: nil, roundRobinIndex: 0)
}

// MARK: - Switch History

struct SwitchEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let fromAccountName: String?
    let fromAccountId: UUID?
    let toAccountName: String
    let toAccountId: UUID
    let reason: String
}

// MARK: - Token Usage

struct AccountTokenUsage: Codable {
    var inputTokens: Int = 0
    var cachedInputTokens: Int = 0
    var outputTokens: Int = 0
    var reasoningTokens: Int = 0
    var sessionCount: Int = 0
    var modelUsage: [String: ModelTokenUsage] = [:]  // model name -> usage

    var totalTokens: Int { inputTokens + outputTokens }
    var effectiveInputTokens: Int { max(0, inputTokens - cachedInputTokens) }

    static func + (lhs: AccountTokenUsage, rhs: AccountTokenUsage) -> AccountTokenUsage {
        var mergedModels = lhs.modelUsage
        for (model, usage) in rhs.modelUsage {
            mergedModels[model, default: ModelTokenUsage()] = mergedModels[model, default: ModelTokenUsage()] + usage
        }
        return AccountTokenUsage(
            inputTokens:       lhs.inputTokens       + rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens,
            outputTokens:      lhs.outputTokens      + rhs.outputTokens,
            reasoningTokens:   lhs.reasoningTokens   + rhs.reasoningTokens,
            sessionCount:      lhs.sessionCount      + rhs.sessionCount,
            modelUsage:        mergedModels
        )
    }
}

/// Per-model token usage tracking
struct ModelTokenUsage: Codable, Equatable {
    var inputTokens: Int = 0
    var cachedInputTokens: Int = 0
    var outputTokens: Int = 0
    var sessionCount: Int = 0

    var totalTokens: Int { inputTokens + outputTokens }

    static func + (lhs: ModelTokenUsage, rhs: ModelTokenUsage) -> ModelTokenUsage {
        ModelTokenUsage(
            inputTokens:       lhs.inputTokens       + rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens,
            outputTokens:      lhs.outputTokens      + rhs.outputTokens,
            sessionCount:      lhs.sessionCount      + rhs.sessionCount
        )
    }
    
    static func += (lhs: inout ModelTokenUsage, rhs: ModelTokenUsage) {
        lhs.inputTokens += rhs.inputTokens
        lhs.cachedInputTokens += rhs.cachedInputTokens
        lhs.outputTokens += rhs.outputTokens
        lhs.sessionCount += rhs.sessionCount
    }
}

// MARK: - Daily Usage (for 7-day chart)

struct DailyUsage: Identifiable {
    let dayStart: Date   // start of calendar day (local timezone)
    let tokens: Int      // total input + output tokens for this day
    var id: TimeInterval { dayStart.timeIntervalSince1970 }
}

// MARK: - Session Event

struct SessionEvent: Codable {
    let timestamp: String
    let type: String
    let payload: PayloadData

    struct PayloadData: Codable {
        let type: String?
        let error: ErrorData?
        let statusCode: Int?

        enum CodingKeys: String, CodingKey {
            case type
            case error
            case statusCode = "status_code"
        }
    }

    struct ErrorData: Codable {
        let code: String?
        let type: String?
        let message: String?
    }
}
