import Foundation

struct AuthCredentials: Sendable {
    let accessToken: String
    let accountId: String
}

struct RateLimitInfo: Sendable {
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

enum FetchResult: Sendable {
    case success(RateLimitInfo)
    case stale
    case failure
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

    func fetch(credentials: AuthCredentials) async -> FetchResult {
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(credentials.accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        req.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            print("[RateLimit] fetch error for \(credentials.accountId): \(error)")
            return .failure
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch statusCode {
        case 200:
            guard let info = parse(data) else { return .failure }
            return .success(info)
        case 401, 403:
            return .stale
        default:
            return .failure
        }
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

        // Pencereleri limit_window_seconds'a göre sınıflandır (CodexBar yaklaşımı)
        // 18000s = 5 saat (session penceresi), 604800s = 7 gün (haftalık pencere)
        // Bu sayede API primary/secondary sıralaması değişse bile doğru çalışır
        let fiveHourMaxSec = 21600  // 6 saat — 5h window için üst eşik

        let (fiveHourWindow, weeklyWindow) = classifyWindows(pw: pw, sw: sw, fiveHourMaxSec: fiveHourMaxSec)

        if let w = weeklyWindow {
            info.weeklyUsedPercent = intVal(w["used_percent"])
            info.weeklyResetAt     = dateVal(w["reset_at"])
        }

        if let h = fiveHourWindow, let used = intVal(h["used_percent"]) {
            info.fiveHourRemainingPercent = max(0, 100 - used)
            info.fiveHourResetAt          = dateVal(h["reset_at"])
        }

        return info
    }

    /// limit_window_seconds değerine bakarak hangi pencere 5h, hangisi haftalık olduğunu belirler.
    private func classifyWindows(
        pw: [String: Any]?,
        sw: [String: Any]?,
        fiveHourMaxSec: Int
    ) -> (fiveHour: [String: Any]?, weekly: [String: Any]?) {
        guard let pw = pw else {
            // Sadece secondary varsa
            guard let sw = sw else { return (nil, nil) }
            let sec = intVal(sw["limit_window_seconds"]) ?? 0
            return sec <= fiveHourMaxSec ? (sw, nil) : (nil, sw)
        }
        guard let sw = sw else {
            // Sadece primary varsa
            let sec = intVal(pw["limit_window_seconds"]) ?? 0
            return sec <= fiveHourMaxSec ? (pw, nil) : (nil, pw)
        }
        // Her ikisi de var — duration'a göre ayırt et
        let pwSec = intVal(pw["limit_window_seconds"]) ?? 0
        let swSec = intVal(sw["limit_window_seconds"]) ?? 0
        if pwSec <= fiveHourMaxSec && swSec > fiveHourMaxSec {
            return (pw, sw)
        } else if swSec <= fiveHourMaxSec && pwSec > fiveHourMaxSec {
            return (sw, pw)
        } else {
            // Duration'dan ayırt edilemiyorsa: position'a göre (varsayılan davranış)
            return (pw, sw)
        }
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
