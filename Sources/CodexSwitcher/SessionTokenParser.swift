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

    func calculate(profiles: [Profile], history: [SwitchEvent]) -> [UUID: AccountTokenUsage] {
        // 1. Disk cache'den kaydedilmiş usage'ları yükle
        let persisted = loadPersistedUsage()

        // 2. Sadece değişen session dosyalarını parse et
        let freshUsage = parseChangedSessions()

        // 3. Persist edilmiş + fresh birleştir
        let merged = mergeUsage(persisted, freshUsage)

        // 4. Session attribution (hangi session hangi hesaba ait)
        let attributed = attributeToProfiles(usage: merged, profiles: profiles, history: history)

        // 5. Sonucu diske kaydet
        savePersistedUsage(merged)

        return attributed
    }

    // MARK: - Change Detection

    /// Sadece son parse'den sonra değişen session dosyalarını bul
    private func parseChangedSessions() -> [String: AccountTokenUsage] {
        let prevModTimes = loadFileModTimes()
        var newModTimes: [String: Date] = prevModTimes // start with existing cache
        var changed: [String: AccountTokenUsage] = [:]

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: sessionsDir,
                                              includingPropertiesForKeys: [.contentModificationDateKey],
                                              options: [.skipsHiddenFiles]) else { return [:] }

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
        return changed
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

    private func attributeToProfiles(usage: [String: AccountTokenUsage], profiles: [Profile], history: [SwitchEvent]) -> [UUID: AccountTokenUsage] {
        guard !usage.isEmpty else { return [:] }

        if history.isEmpty {
            guard let active = profiles
                .filter({ $0.activatedAt != nil })
                .max(by: { $0.activatedAt! < $1.activatedAt! }) else { return [:] }
            let total = usage.values.reduce(AccountTokenUsage()) { $0 + $1 }
            if total.totalTokens > 0 { return [active.id: total] }
            return [:]
        }

        // Her session'ın başlangıç tarihini al, hangi hesabın aktif olduğunu bul
        var result: [UUID: AccountTokenUsage] = [:]
        for (sessionPath, sessionUsage) in usage {
            let sessionDate = sessionStartDateFromPath(sessionPath) ?? Date()
            let activeProfile = findActiveProfile(at: sessionDate, profiles: profiles, history: history)
            guard let profileId = activeProfile else { continue }
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
        // "2026-03-31T02-50-56.jsonl" veya "2026-03-31T025056.jsonl" formatları
        let base = (name as NSString).deletingPathExtension
        // T ve -/_ karakterlerini normalize et
        let normalized = base
            .replacingOccurrences(of: "T", with: " ")
            .replacingOccurrences(of: "-", with: ":", range: base.range(of: "\\d{2}[-_]\\d{2}[-_]\\d{2}", options: .regularExpression) ?? nil)
            .replacingOccurrences(of: "_", with: ":")
        // "2026-03-31 02:50:56" formatını dene
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        if let d = df.date(from: normalized) { return d }
        // Sadece tarih kısmı
        let dateOnly = String(name.prefix(10))
        guard dateOnly.count == 10, dateOnly.contains("-") else { return nil }
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: dateOnly)
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

        for line in content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty,
                  let data = t.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["type"] as? String == "event_msg",
                  let payload = json["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any]
            else { continue }

            last = AccountTokenUsage(
                inputTokens:       (total["input_tokens"]            as? Int) ?? 0,
                cachedInputTokens: (total["cached_input_tokens"]     as? Int) ?? 0,
                outputTokens:      (total["output_tokens"]           as? Int) ?? 0,
                reasoningTokens:   (total["reasoning_output_tokens"] as? Int) ?? 0,
                sessionCount:      1
            )
            found = true
        }
        return found ? last : AccountTokenUsage()
    }
}
