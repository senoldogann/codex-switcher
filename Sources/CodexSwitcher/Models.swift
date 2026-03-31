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

    var totalTokens: Int { inputTokens + outputTokens }
    /// Cache'lenmemiş gerçek input (faturalandırılabilir)
    var effectiveInputTokens: Int { max(0, inputTokens - cachedInputTokens) }

    static func + (lhs: AccountTokenUsage, rhs: AccountTokenUsage) -> AccountTokenUsage {
        AccountTokenUsage(
            inputTokens:       lhs.inputTokens       + rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens,
            outputTokens:      lhs.outputTokens      + rhs.outputTokens,
            reasoningTokens:   lhs.reasoningTokens   + rhs.reasoningTokens,
            sessionCount:      lhs.sessionCount      + rhs.sessionCount
        )
    }
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
