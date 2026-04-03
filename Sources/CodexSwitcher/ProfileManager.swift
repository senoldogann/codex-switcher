import Foundation

/// Profilleri ~/.codex-switcher/ altında saklar ve auth.json geçişlerini yönetir.
final class ProfileManager: @unchecked Sendable {

    // MARK: - Paths

    static let switcherDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".codex-switcher")
    }()

    static let profilesDir: URL = {
        switcherDir.appendingPathComponent("profiles")
    }()

    static let configPath: URL = {
        switcherDir.appendingPathComponent("config.json")
    }()

    static let codexAuthPath: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
    }()

    static let authBackupPath: URL = {
        switcherDir.appendingPathComponent("auth-backup.json")
    }()

    // MARK: - Bootstrap

    func bootstrap() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.switcherDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: Self.profilesDir, withIntermediateDirectories: true)
    }

    // MARK: - Auth Recovery

    /// Verify auth.json on boot and recover if broken. Must run BEFORE loadProfiles().
    func verifyAndRecoverActiveAuth() -> AuthVerificationResult {
        if FileManager.default.fileExists(atPath: Self.authBackupPath.path) {
            try? FileManager.default.removeItem(at: Self.authBackupPath)
        }

        let config = loadConfig()
        guard let activeId = config.activeProfileId,
              let activeProfile = config.profiles.first(where: { $0.id == activeId }) else {
            return .valid
        }

        if isValidAuthFile(at: Self.codexAuthPath, expectedAccountId: activeProfile.accountId) {
            return .valid
        }

        let profileAuthPath = authPath(for: activeProfile)
        if FileManager.default.fileExists(atPath: profileAuthPath.path),
           let data = try? Data(contentsOf: profileAuthPath),
           isValidAuthData(data) {
            do {
                try data.write(to: Self.codexAuthPath, options: .atomic)
                return .recovered
            } catch {
                print("[AuthRecovery] recovery write failed: \(error)")
                return .unrecoverable
            }
        }

        return .unrecoverable
    }

    private func isValidAuthFile(at url: URL, expectedAccountId: String) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = dict["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String else { return false }
        guard let actualId = extractAccountId(from: accessToken) else { return false }
        return actualId == expectedAccountId
    }

    private func isValidAuthData(_ data: Data) -> Bool {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = dict["tokens"] as? [String: Any],
              tokens["access_token"] as? String != nil else { return false }
        return true
    }

    // MARK: - Config I/O

    func loadConfig() -> AppConfig {
        guard let data = try? Data(contentsOf: Self.configPath),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return .empty
        }
        return config
    }

    func saveConfig(_ config: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: Self.configPath, options: .atomic)
    }

    // MARK: - Profile Auth Paths

    func authPath(for profile: Profile) -> URL {
        Self.profilesDir
            .appendingPathComponent(profile.id.uuidString)
            .appendingPathExtension("json")
    }

    /// Path for Claude Code credential blob (separate from Codex auth JSON)
    func claudeAuthPath(for profile: Profile) -> URL {
        Self.profilesDir
            .appendingPathComponent(profile.id.uuidString)
            .appendingPathExtension("claudeauth")
    }

    // MARK: - Auth Read Helpers

    func readAuthDict(for profile: Profile) -> [String: Any]? {
        guard let data = try? Data(contentsOf: authPath(for: profile)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func readLiveAuthDict() -> [String: Any]? {
        guard let data = try? Data(contentsOf: Self.codexAuthPath) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - Capture Current Auth (provider-aware)

    func captureCurrentAuth(alias: String, provider: AIProvider = .codex) -> Profile? {
        switch provider {
        case .codex:      return captureCodexAuth(alias: alias)
        case .claudeCode: return captureClaudeCodeAuth(alias: alias)
        }
    }

    private func captureCodexAuth(alias: String) -> Profile? {
        guard let data = try? Data(contentsOf: Self.codexAuthPath),
              let authDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = authDict["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              let accountId = extractAccountId(from: accessToken) else { return nil }

        let email = extractEmail(from: accessToken) ?? "unknown@codex"
        let profile = Profile(id: UUID(), alias: alias, email: email,
                              accountId: accountId, addedAt: Date(), aiProvider: .codex)
        try? data.write(to: authPath(for: profile), options: .atomic)
        return profile
    }

    func captureClaudeCodeAuth(alias: String) -> Profile? {
        guard let data = ClaudeCodeManager.readCredentialsData(),
              let email = ClaudeCodeManager.parseEmail(from: data),
              let accountId = ClaudeCodeManager.parseAccountId(from: data) else { return nil }

        let profile = Profile(id: UUID(), alias: alias, email: email,
                              accountId: accountId, addedAt: Date(), aiProvider: .claudeCode)
        try? data.write(to: claudeAuthPath(for: profile), options: .atomic)
        return profile
    }

    // MARK: - Activate (provider-aware)

    @discardableResult
    func activate(profile: Profile) throws -> VerifyResult {
        switch profile.aiProvider {
        case .codex:      return try activateCodex(profile: profile)
        case .claudeCode: return try activateClaudeCode(profile: profile)
        }
    }

    private func activateCodex(profile: Profile) throws -> VerifyResult {
        let src = authPath(for: profile)
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw SwitcherError.missingAuthFile(profile.email)
        }
        let newData = try Data(contentsOf: src)

        if FileManager.default.fileExists(atPath: Self.codexAuthPath.path) {
            do { try FileManager.default.copyItem(at: Self.codexAuthPath, to: Self.authBackupPath) }
            catch { print("[AuthBackup] backup failed: \(error)") }
        }

        let tmp = Self.codexAuthPath.deletingLastPathComponent()
            .appendingPathComponent(".auth_tmp_\(UUID().uuidString).json")
        do {
            try newData.write(to: tmp, options: [])
            guard try FileManager.default.replaceItemAt(Self.codexAuthPath, withItemAt: tmp) != nil else {
                try? FileManager.default.removeItem(at: tmp)
                throw SwitcherError.activationFailed(profile.email)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }

        let verifyResult = verifyActiveAccount(expectedAccountId: profile.accountId)
        if case .failed = verifyResult {
            if FileManager.default.fileExists(atPath: Self.authBackupPath.path) {
                do { try FileManager.default.replaceItemAt(Self.codexAuthPath, withItemAt: Self.authBackupPath) }
                catch { print("[AuthRollback] rollback failed: \(error)") }
            }
        } else {
            try? FileManager.default.removeItem(at: Self.authBackupPath)
        }
        return verifyResult
    }

    private func activateClaudeCode(profile: Profile) throws -> VerifyResult {
        let path = claudeAuthPath(for: profile)
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path) else {
            throw SwitcherError.missingAuthFile(profile.email)
        }
        guard ClaudeCodeManager.writeCredentialsData(data) else {
            throw SwitcherError.activationFailed(profile.email)
        }
        // Verify by reading back
        guard let written = ClaudeCodeManager.readCredentialsData(),
              let actualId = ClaudeCodeManager.parseAccountId(from: written) else {
            return .failed(.jwtParseFailed)
        }
        return actualId == profile.accountId ? .verified
             : .failed(.mismatch(expected: profile.accountId, actual: actualId))
    }

    // MARK: - Verify Active Account

    func verifyActiveAccount(expectedAccountId: String) -> VerifyResult {
        guard FileManager.default.fileExists(atPath: Self.codexAuthPath.path) else {
            return .failed(.fileMissing)
        }
        guard let data = try? Data(contentsOf: Self.codexAuthPath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = dict["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String else {
            return .failed(.invalidJSON)
        }
        guard let actualId = extractAccountId(from: accessToken) else {
            return .failed(.jwtParseFailed)
        }
        guard !actualId.isEmpty else { return .failed(.claimNotFound) }
        return actualId == expectedAccountId ? .verified
             : .failed(.mismatch(expected: expectedAccountId, actual: actualId))
    }

    func verifyClaudeCodeAccount(expectedAccountId: String) -> VerifyResult {
        guard let data = ClaudeCodeManager.readCredentialsData() else { return .failed(.fileMissing) }
        guard let actualId = ClaudeCodeManager.parseAccountId(from: data) else { return .failed(.jwtParseFailed) }
        return actualId == expectedAccountId ? .verified
             : .failed(.mismatch(expected: expectedAccountId, actual: actualId))
    }

    func deleteProfile(_ profile: Profile) {
        try? FileManager.default.removeItem(at: authPath(for: profile))
        try? FileManager.default.removeItem(at: claudeAuthPath(for: profile))
    }

    // MARK: - JWT Helpers

    func extractEmail(from jwt: String) -> String? {
        extractClaim(from: jwt, keyPath: ["https://api.openai.com/profile", "email"])
    }

    func extractAccountId(from jwt: String) -> String? {
        extractClaim(from: jwt, keyPath: ["https://api.openai.com/auth", "chatgpt_account_id"])
    }

    private func extractClaim(from jwt: String, keyPath: [String]) -> String? {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }

        var b64 = parts[1]
        let remainder = b64.count % 4
        if remainder != 0 { b64 += String(repeating: "=", count: 4 - remainder) }

        guard let payloadData = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }

        var current: Any = json as Any
        for (i, key) in keyPath.enumerated() {
            if i == keyPath.count - 1 {
                return (current as? [String: Any])?[key] as? String
            }
            guard let next = (current as? [String: Any])?[key] else { return nil }
            current = next
        }
        return nil
    }
}

enum SwitcherError: LocalizedError {
    case missingAuthFile(String)
    case noProfilesAvailable
    case allProfilesExhausted
    case activationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAuthFile(let email):
            return "Auth dosyası bulunamadı: \(email)"
        case .noProfilesAvailable:
            return "Henüz hesap eklenmedi."
        case .allProfilesExhausted:
            return "Tüm hesapların limiti doldu!"
        case .activationFailed(let email):
            return "Aktivasyon başarısız: \(email)"
        }
    }
}

enum AuthVerificationResult {
    case valid
    case recovered
    case unrecoverable
}

enum VerifyResult: Equatable {
    case verified
    case failed(VerifyError)
}

enum VerifyError: Equatable {
    case fileMissing
    case invalidJSON
    case jwtParseFailed
    case claimNotFound
    case mismatch(expected: String, actual: String)
}
