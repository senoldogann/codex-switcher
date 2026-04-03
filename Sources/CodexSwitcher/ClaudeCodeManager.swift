import Foundation
import Security

/// Manages Claude Code credentials stored in macOS Keychain.
/// Claude Code stores auth as JSON under service "Claude Code-credentials".
/// Schema: { claudeAiOauth: { accessToken, refreshToken, expiresAt, scopes,
///                             subscriptionType, rateLimitTier }, organizationUuid }
struct ClaudeCodeManager: Sendable {

    private static let keychainService = "Claude Code-credentials"

    // MARK: - Keychain R/W

    static func readCredentialsData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }

    @discardableResult
    static func writeCredentialsData(_ data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]
        var status = SecItemUpdate(query as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    // MARK: - Credential Parsing

    /// Email extracted from the OAuth access token JWT.
    static func parseEmail(from data: Data) -> String? {
        guard let jwt = oauthAccessToken(from: data) else { return nil }
        return jwtClaim("email", in: jwt)
    }

    /// Stable account identifier: organizationUuid → JWT "sub" → token prefix hash.
    static func parseAccountId(from data: Data) -> String? {
        if let json = jsonDict(from: data),
           let orgId = json["organizationUuid"] as? String, !orgId.isEmpty {
            return orgId
        }
        if let jwt = oauthAccessToken(from: data) {
            // Try JWT sub claim (only works for JWT-format tokens)
            if let sub = jwtClaim("sub", in: jwt) { return sub }
            // Opaque token: use first 16 chars as stable prefix ID
            if jwt.count >= 16 { return String(jwt.prefix(16)) }
        }
        return nil
    }

    static func parseSubscriptionType(from data: Data) -> String? {
        guard let json = jsonDict(from: data),
              let oauth = json["claudeAiOauth"] as? [String: Any] else { return nil }
        return oauth["subscriptionType"] as? String
    }

    /// Human-readable label when email is not extractable (opaque tokens).
    /// Returns e.g. "Pro Account" or "Claude Code Account".
    static func parseDisplayLabel(from data: Data) -> String? {
        guard let sub = parseSubscriptionType(from: data) else { return nil }
        let capitalized = sub.prefix(1).uppercased() + sub.dropFirst()
        return "\(capitalized) Account"
    }

    // MARK: - Helpers

    private static func oauthAccessToken(from data: Data) -> String? {
        guard let json = jsonDict(from: data),
              let oauth = json["claudeAiOauth"] as? [String: Any] else { return nil }
        return oauth["accessToken"] as? String
    }

    private static func jsonDict(from data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func jwtClaim(_ key: String, in jwt: String) -> String? {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = parts[1]
        let rem = b64.count % 4
        if rem != 0 { b64 += String(repeating: "=", count: 4 - rem) }
        guard let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return dict[key] as? String
    }
}
