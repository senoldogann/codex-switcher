import Foundation

// MARK: - AI Provider

enum AIProvider: String, Codable, CaseIterable {
    case codex = "codex"

    var displayName: String { "Codex" }
    var shortBadge: String { "CX" }

    /// OS process name used to find/kill the running app
    var processName: String { "Codex" }

    /// Login command run in background to trigger auth
    var loginCommand: [String] { ["codex", "login"] }
}

// MARK: - Profile

struct Profile: Identifiable, Codable, Equatable {
    let id: UUID
    var alias: String
    var email: String
    var accountId: String
    var addedAt: Date
    var activatedAt: Date?
    var lastKnownTurns: Int?
    var aiProvider: AIProvider

     init(id: UUID = UUID(), alias: String, email: String, accountId: String,
         addedAt: Date, activatedAt: Date? = nil, lastKnownTurns: Int? = nil,
         aiProvider: AIProvider = .codex) {
        self.id = id; self.alias = alias; self.email = email
        self.accountId = accountId; self.addedAt = addedAt
        self.activatedAt = activatedAt; self.lastKnownTurns = lastKnownTurns
        self.aiProvider = .codex
    }

    // Backward-compatible decoder: old profiles missing aiProvider default to .codex
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self,   forKey: .id)
        alias         = try c.decode(String.self, forKey: .alias)
        email         = try c.decode(String.self, forKey: .email)
        accountId     = try c.decode(String.self, forKey: .accountId)
        addedAt       = try c.decode(Date.self,   forKey: .addedAt)
        activatedAt   = try c.decodeIfPresent(Date.self,       forKey: .activatedAt)
        lastKnownTurns = try c.decodeIfPresent(Int.self,       forKey: .lastKnownTurns)
        aiProvider    = try c.decodeIfPresent(AIProvider.self, forKey: .aiProvider) ?? .codex
    }

    var displayName: String { alias.isEmpty ? email : alias }

    var shortEmail: String {
        let local = email.components(separatedBy: "@").first ?? email
        return local.count > 14 ? String(local.prefix(14)) + "…" : local
    }

    var initial: String { String(displayName.prefix(1).uppercased()) }
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

// MARK: - Codex Insights

struct ProjectUsage: Identifiable {
    let id: String          // cwd path as stable key
    let name: String        // last path component
    let path: String
    let tokens: Int
    let cost: Double
    let sessionCount: Int
    let lastUsed: Date
}

struct SessionSummary: Identifiable {
    let id: String          // session UUID
    let projectName: String
    let projectPath: String
    let firstPrompt: String
    let tokens: Int
    let timestamp: Date
    let depth: Int
    let agentRole: String
    let parentId: String?   // nil = root session
}

struct HourlyActivity: Identifiable {
    let hour: Int           // 0–23
    let dayOfWeek: Int      // 0=Mon … 6=Sun
    let tokens: Int
    var id: String { "\(dayOfWeek)-\(hour)" }
}

struct ExpensiveTurn: Identifiable {
    let id: String
    let projectName: String
    let promptPreview: String
    let inputTokens: Int
    let outputTokens: Int
    let cost: Double
    let timestamp: Date
    let model: String

    var tokens: Int { inputTokens + outputTokens }
}

struct CodexInsights {
    let projects: [ProjectUsage]
    let sessions: [SessionSummary]
    let hourlyActivity: [HourlyActivity]
    let expensiveTurns: [ExpensiveTurn]

    static let empty = CodexInsights(projects: [], sessions: [], hourlyActivity: [], expensiveTurns: [])
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
