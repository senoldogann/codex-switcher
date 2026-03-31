import Foundation

struct AuthCredentials: Sendable {
    let accessToken: String
    let accountId: String
}

struct RateLimitInfo {
    var planType: String = "free"
    var allowed: Bool = true
    var limitReached: Bool = false

    // Haftalık kullanım (used %) — bar dolunca tükeniyor
    var weeklyUsedPercent: Int?
    var weeklyResetAt: Date?

    // 5 saatlik kalan (remaining %) — Codex IDE ile aynı format
    // 100 = tam dolu (iyi), 0 = tükenmiş
    var fiveHourRemainingPercent: Int?
    var fiveHourResetAt: Date?

    /// Gösterim için kalan haftalık % (Codex IDE formatı)
    var weeklyRemainingPercent: Int? {
        weeklyUsedPercent.map { max(0, 100 - $0) }
    }

    var isPlus: Bool {
        let freeNames = ["free", "guest", ""]
        return !freeNames.contains(planType.lowercased())
    }

    var weeklyResetLabel: String {
        guard let date = weeklyResetAt else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.dateFormat = "d MMM"
        return fmt.string(from: date)
    }

    var fiveHourResetLabel: String {
        guard let date = fiveHourResetAt else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }
}

final class RateLimitFetcher: @unchecked Sendable {

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        return URLSession(configuration: config)
    }()

    func credentials(from authDict: [String: Any]) -> AuthCredentials? {
        guard let tokens = authDict["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String else { return nil }
        return AuthCredentials(accessToken: access, accountId: tokens["account_id"] as? String ?? "")
    }

    func fetch(credentials: AuthCredentials) async -> RateLimitInfo? {
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(credentials.accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        req.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: req) else { return nil }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            print("[RateLimit] fetch failed for \(credentials.accountId), status: \(statusCode)")
            return nil
        }
        return parse(data)
    }

    private func parse(_ data: Data) -> RateLimitInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var info = RateLimitInfo()
        info.planType = json["plan_type"] as? String ?? "free"

        guard let rl = json["rate_limit"] as? [String: Any] else { return info }

        info.allowed      = rl["allowed"]       as? Bool ?? true
        info.limitReached = rl["limit_reached"] as? Bool ?? false

        let pw = rl["primary_window"]   as? [String: Any]
        let sw = rl["secondary_window"] as? [String: Any]

        if let sw {
            // Plus/Pro: secondary_window = haftalık (used %)
            info.weeklyUsedPercent = intVal(sw["used_percent"])
            info.weeklyResetAt     = dateVal(sw["reset_at"])

            // primary_window = 5 saatlik → Codex IDE gibi KALAN (remaining) göster
            if let pw, let used = intVal(pw["used_percent"]) {
                info.fiveHourRemainingPercent = max(0, 100 - used)
                info.fiveHourResetAt          = dateVal(pw["reset_at"])
            }
        } else if let pw {
            // Free: sadece primary_window var = haftalık (used %)
            info.weeklyUsedPercent = intVal(pw["used_percent"])
            info.weeklyResetAt     = dateVal(pw["reset_at"])
        }

        return info
    }

    /// JSON sayısı Int veya Double olabilir.
    private func intVal(_ v: Any?) -> Int? {
        guard let v else { return nil }
        if let i = v as? Int    { return i }
        if let d = v as? Double { return Int(d) }
        return nil
    }

    /// Unix timestamp → Date (Int veya Double).
    private func dateVal(_ v: Any?) -> Date? {
        guard let v else { return nil }
        if let d = v as? Double { return Date(timeIntervalSince1970: d) }
        if let i = v as? Int    { return Date(timeIntervalSince1970: Double(i)) }
        return nil
    }
}
