import Foundation

/// ~/.codex/sessions/ dosyalarını parse ederek hesap başına token kullanımını hesaplar.
/// Her session, aktif olan hesaba attribution edilir (switch history ile).
/// Sonuçlar disk'e kaydedilir — app restart'ta kaybolmaz.
final class SessionTokenParser: @unchecked Sendable {

    private let sessionsDir: URL
    private let iso8601: ISO8601DateFormatter
    private let cacheDir: URL
    private let cacheURL: URL
    private let fileModCacheKey = "fileModTimes"

    init() {
        sessionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-switcher")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        cacheDir = base.appendingPathComponent("cache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        cacheURL = cacheDir.appendingPathComponent("token-usage.json")
    }

    private func parseDate(_ ts: String) -> Date? {
        if let d = iso8601.date(from: ts) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: ts) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            df.dateFormat = fmt
            if let d = df.date(from: ts) { return d }
        }
        return nil
    }

    // MARK: - Public

    func calculate(profiles: [Profile], history: [SwitchEvent], activeProfileId: UUID? = nil) -> [UUID: AccountTokenUsage] {
        // 1. Disk cache'den kaydedilmiş usage'ları yükle
        let persisted = loadPersistedUsage()

        // 2. Sadece değişen session dosyalarını parse et (mod zamanlarıyla birlikte)
        let (freshUsage, freshModTimes) = parseChangedSessionsWithModTimes()

        // 3. Persist edilmiş + fresh birleştir
        let merged = mergeUsage(persisted, freshUsage)

        // 4. Session attribution (hangi session hangi hesaba ait)
        // Mevcut mod zamanlarını persisted + fresh birleştir
        let allModTimes = mergeModTimes(loadFileModTimes(), freshModTimes)
        let attributed = attributeToProfiles(
            usage: merged,
            modTimes: allModTimes,
            profiles: profiles,
            history: history,
            activeProfileId: activeProfileId
        )

        // 5. Sonucu diske kaydet
        savePersistedUsage(merged)

        return attributed
    }

    // MARK: - Change Detection

    /// Sadece son parse'den sonra değişen session dosyalarını bul; mod zamanlarını da döner.
    private func parseChangedSessionsWithModTimes() -> ([String: AccountTokenUsage], [String: Date]) {
        let prevModTimes = loadFileModTimes()
        var newModTimes: [String: Date] = prevModTimes // start with existing cache
        var changed: [String: AccountTokenUsage] = [:]

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: sessionsDir,
                                              includingPropertiesForKeys: [.contentModificationDateKey],
                                              options: [.skipsHiddenFiles]) else { return ([:], [:]) }

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            newModTimes[url.path] = modDate

            let prev = prevModTimes[url.path]
            if prev == nil || prev != modDate {
                // New or changed file — parse it
                guard sessionStartDate(at: url) != nil else { continue }
                let usage = finalTokenUsage(at: url)
                if usage.totalTokens > 0 {
                    changed[url.path] = usage
                }
            }
        }

        // Remove deleted files from cache
        for path in prevModTimes.keys where newModTimes[path] == nil {
            newModTimes.removeValue(forKey: path)
        }

        saveFileModTimes(newModTimes)
        return (changed, newModTimes)
    }

    private func mergeModTimes(_ a: [String: Date], _ b: [String: Date]) -> [String: Date] {
        var merged = a
        for (key, value) in b { merged[key] = value }
        return merged
    }

    // MARK: - File Modification Time Cache

    private func loadFileModTimes() -> [String: Date] {
        guard let data = try? Data(contentsOf: cacheURL.appendingPathExtension("mod")),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Double] else {
            return [:]
        }
        return dict.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private func saveFileModTimes(_ times: [String: Date]) {
        let dict = times.mapValues { $0.timeIntervalSince1970 }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? data.write(to: cacheURL.appendingPathExtension("mod"), options: .atomic)
    }

    // MARK: - Persisted Usage

    private func loadPersistedUsage() -> [String: AccountTokenUsage] {
        guard let data = try? Data(contentsOf: cacheURL),
              let dict = try? JSONDecoder().decode([String: AccountTokenUsage].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func savePersistedUsage(_ usage: [String: AccountTokenUsage]) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func mergeUsage(_ persisted: [String: AccountTokenUsage], _ fresh: [String: AccountTokenUsage]) -> [String: AccountTokenUsage] {
        var merged = persisted
        for (path, usage) in fresh {
            merged[path] = usage
        }
        return merged
    }

    // MARK: - Attribution

    private func attributeToProfiles(usage: [String: AccountTokenUsage], modTimes: [String: Date], profiles: [Profile], history: [SwitchEvent], activeProfileId: UUID? = nil) -> [UUID: AccountTokenUsage] {
        guard !usage.isEmpty else { return [:] }

        // Last switch timestamp — sessions modified after this are live under the current account
        let lastSwitchTime = history.max(by: { $0.timestamp < $1.timestamp })?.timestamp

        if history.isEmpty {
            guard let active = profiles
                .filter({ $0.activatedAt != nil })
                .max(by: { $0.activatedAt! < $1.activatedAt! }) else { return [:] }
            let total = usage.values.reduce(AccountTokenUsage()) { $0 + $1 }
            if total.totalTokens > 0 { return [active.id: total] }
            return [:]
        }

        var result: [UUID: AccountTokenUsage] = [:]
        for (sessionPath, sessionUsage) in usage {
            let profileId: UUID?

            // If the session file was modified after the last account switch and we know
            // who is active now, attribute it to the current account — the session is
            // still live and accumulating tokens under the current login.
            if let activeProfileId = activeProfileId,
               let lastSwitch = lastSwitchTime,
               let modDate = modTimes[sessionPath],
               modDate > lastSwitch {
                profileId = activeProfileId
            } else {
                let sessionDate = sessionStartDateFromPath(sessionPath) ?? Date()
                profileId = findActiveProfile(at: sessionDate, profiles: profiles, history: history)
            }

            guard let profileId = profileId else { continue }
            result[profileId, default: AccountTokenUsage()] = result[profileId, default: AccountTokenUsage()] + sessionUsage
        }
        return result
    }

    private func findActiveProfile(at date: Date, profiles: [Profile], history: [SwitchEvent]) -> UUID? {
        // Bu tarihte hangi hesap aktifti?
        // History'deki switch event'lerine bak: date anında en son hangi hesaba geçilmiş
        let relevantSwitches = history.filter { $0.timestamp <= date }
        guard let lastSwitch = relevantSwitches.max(by: { $0.timestamp < $1.timestamp }) else {
            // History'den önce → en eski aktif profil
            return profiles
                .filter { $0.activatedAt != nil }
                .min(by: { $0.activatedAt! < $1.activatedAt! })?
                .id
        }
        return lastSwitch.toAccountId
    }

    private func sessionStartDateFromPath(_ path: String) -> Date? {
        // Dosya adından tarih çıkarmayı dene (YYYY/MM/DD/YYYY-MM-DDThhmmss.jsonl gibi)
        let components = path.components(separatedBy: "/")
        for component in components.reversed() {
            if let date = parseDateFromFilename(component) {
                return date
            }
        }
        return nil
    }

    private func parseDateFromFilename(_ name: String) -> Date? {
        let base = (name as NSString).deletingPathExtension
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")

        // "rollout-2026-03-18T21-57-46-UUID" ve "YYYY-MM-DDThh-mm-ss" formatları:
        // Filename içinde YYYY-MM-DDThh-mm-ss kalıbını regex ile bul
        if let tsRange = base.range(of: #"\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}"#, options: .regularExpression) {
            let ts = String(base[tsRange]) // "2026-03-18T21-57-46"
            let datePart = String(ts.prefix(10))        // "2026-03-18"
            let timePart = String(ts.dropFirst(11))     // "21-57-46"
            let normalized = datePart + " " + timePart.replacingOccurrences(of: "-", with: ":")
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let d = df.date(from: normalized) { return d }
        }

        // "YYYY-MM-DDTHHmmss" formatı (eski stil, bölme karaktersiz zaman)
        let normalized = base
            .replacingOccurrences(of: "T", with: " ")
            .replacingOccurrences(of: "-", with: ":", range: base.range(of: "\\d{2}[-_]\\d{2}[-_]\\d{2}", options: .regularExpression) ?? nil)
            .replacingOccurrences(of: "_", with: ":")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = df.date(from: normalized) { return d }

        // Sadece tarih kısmını filename içinde bul (YYYY-MM-DD)
        if let dateRange = base.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            df.dateFormat = "yyyy-MM-dd"
            return df.date(from: String(base[dateRange]))
        }
        return nil
    }

    // MARK: - Session Parsing

    private func sessionStartDate(at url: URL) -> Date? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let firstLine = content.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        guard let jsonData = firstLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let ts = json["timestamp"] as? String else { return nil }
        return parseDate(ts)
    }

    private func finalTokenUsage(at url: URL) -> AccountTokenUsage {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return AccountTokenUsage() }
        var last = AccountTokenUsage()
        var found = false
        var currentModel: String? = nil

        for line in content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty,
                  let data = t.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let type = json["type"] as? String

            // Track model from turn_context
            if type == "turn_context" {
                if let payload = json["payload"] as? [String: Any] {
                    if let model = payload["model"] as? String {
                        currentModel = normalizeModel(model)
                    } else if let info = payload["info"] as? [String: Any], let model = info["model"] as? String {
                        currentModel = normalizeModel(model)
                    }
                }
                continue
            }

            // Track token counts
            guard type == "event_msg" else { continue }
            guard let payload = json["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any]
            else { continue }

            // Determine model for this token count
            let modelFromInfo = info["model"] as? String ?? info["model_name"] as? String
            let modelFromPayload = payload["model"] as? String
            let modelFromRoot = json["model"] as? String
            let effectiveModel = modelFromInfo ?? modelFromPayload ?? modelFromRoot ?? currentModel ?? "gpt-5"
            let normalizedModel = normalizeModel(effectiveModel)

            let input = (total["input_tokens"] as? NSNumber)?.intValue ?? 0
            let cached = (total["cached_input_tokens"] as? NSNumber)?.intValue ?? (total["cache_read_input_tokens"] as? NSNumber)?.intValue ?? 0
            let output = (total["output_tokens"] as? NSNumber)?.intValue ?? 0

            last = AccountTokenUsage(
                inputTokens: input,
                cachedInputTokens: cached,
                outputTokens: output,
                reasoningTokens: 0,
                sessionCount: 1,
                modelUsage: [normalizedModel: ModelTokenUsage(
                    inputTokens: input,
                    cachedInputTokens: cached,
                    outputTokens: output,
                    sessionCount: 1
                )]
            )
            found = true
        }
        return found ? last : AccountTokenUsage()
    }

    /// Normalize model name to match pricing keys
    private func normalizeModel(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("openai/") {
            trimmed = String(trimmed.dropFirst("openai/".count))
        }
        // Strip date suffix: gpt-5-2025-01-15 -> gpt-5
        if let datedSuffix = trimmed.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            let base = String(trimmed[..<datedSuffix.lowerBound])
            let knownModels = ["gpt-5", "gpt-5-mini", "gpt-5-nano", "gpt-5-pro",
                               "gpt-5.1", "gpt-5.1-codex", "gpt-5.1-codex-max", "gpt-5.1-codex-mini",
                               "gpt-5.2", "gpt-5.2-codex", "gpt-5.2-pro",
                               "gpt-5.3-codex", "gpt-5.3-codex-spark",
                               "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano", "gpt-5.4-pro"]
            if knownModels.contains(base) {
                return base
            }
        }
        return trimmed
    }
}
