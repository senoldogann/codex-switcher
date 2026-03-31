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

    // MARK: - Bootstrap

    func bootstrap() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.switcherDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: Self.profilesDir, withIntermediateDirectories: true)
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

    // MARK: - Profile Auth I/O

    func authPath(for profile: Profile) -> URL {
        Self.profilesDir
            .appendingPathComponent(profile.id.uuidString)
            .appendingPathExtension("json")
    }

    /// Belirli bir profilin auth.json sözlüğünü döner (rate limit fetch için)
    func readAuthDict(for profile: Profile) -> [String: Any]? {
        guard let data = try? Data(contentsOf: authPath(for: profile)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Mevcut ~/.codex/auth.json'u okuyup yeni profil olarak kaydeder
    func captureCurrentAuth(alias: String) -> Profile? {
        guard let data = try? Data(contentsOf: Self.codexAuthPath),
              let authDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = authDict["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              let accountId = extractAccountId(from: accessToken) else {
            return nil
        }

        let email = extractEmail(from: accessToken) ?? "bilinmeyen@hesap.com"
        let profile = Profile(
            id: UUID(),
            alias: alias,
            email: email,
            accountId: accountId,
            addedAt: Date()
        )

        // auth.json'u bu profilin dizinine kopyala
        try? data.write(to: authPath(for: profile), options: .atomic)
        return profile
    }

    /// Profili aktif et — auth.json'u atomik olarak değiştir
    func activate(profile: Profile) throws {
        let src = authPath(for: profile)
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw SwitcherError.missingAuthFile(profile.email)
        }

        let data = try Data(contentsOf: src)
        // Atomic write: temp → rename
        let tmp = Self.codexAuthPath.deletingLastPathComponent()
            .appendingPathComponent(".auth_tmp_\(UUID().uuidString).json")
        try data.write(to: tmp, options: .atomic)
        _ = try? FileManager.default.replaceItemAt(Self.codexAuthPath, withItemAt: tmp)
    }

    func deleteProfile(_ profile: Profile) {
        try? FileManager.default.removeItem(at: authPath(for: profile))
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

    var errorDescription: String? {
        switch self {
        case .missingAuthFile(let email):
            return "Auth dosyası bulunamadı: \(email)"
        case .noProfilesAvailable:
            return "Henüz hesap eklenmedi."
        case .allProfilesExhausted:
            return "Tüm hesapların limiti doldu!"
        }
    }
}
