import Foundation

/// ~/.codex/sessions/ dosyalarını parse ederek hesap başına token kullanımını hesaplar.
final class SessionTokenParser {

    private let sessionsDir: URL
    private let iso8601: ISO8601DateFormatter

    init() {
        sessionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func calculate(profiles: [Profile], history: [SwitchEvent]) -> [UUID: AccountTokenUsage] {
        let allSessions = collectAllSessions()
        guard !allSessions.isEmpty else { return [:] }

        var result: [UUID: AccountTokenUsage] = [:]

        if history.isEmpty {
            // History henüz yok → en son aktivite edilen profile tüm session toplamını göster
            guard let active = profiles
                .filter({ $0.activatedAt != nil })
                .max(by: { $0.activatedAt! < $1.activatedAt! }) else { return [:] }
            let total = allSessions.reduce(AccountTokenUsage()) { $0 + $1.1 }
            if total.totalTokens > 0 { result[active.id] = total }
            return result
        }

        // History varsa → her profil için aktif dönemdeki session'ları attribute et
        for profile in profiles {
            guard let activatedAt = profile.activatedAt else { continue }

            // Hesap ne zaman devre dışı bırakıldı (başkası aktive edildi)?
            let deactivatedAt: Date = history
                .filter { $0.fromAccountId == profile.id }
                .map { $0.timestamp }
                .min() ?? Date()

            var total = AccountTokenUsage()
            for (startDate, usage) in allSessions where startDate >= activatedAt && startDate <= deactivatedAt {
                total = total + usage
            }
            if total.totalTokens > 0 { result[profile.id] = total }
        }
        return result
    }

    // MARK: - Private

    private func collectAllSessions() -> [(Date, AccountTokenUsage)] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: sessionsDir,
                                              includingPropertiesForKeys: [.isRegularFileKey],
                                              options: [.skipsHiddenFiles]) else { return [] }
        var results: [(Date, AccountTokenUsage)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let start = sessionStartDate(at: url) else { continue }
            let usage = finalTokenUsage(at: url)
            guard usage.totalTokens > 0 else { continue }
            results.append((start, usage))
        }
        return results
    }

    private func sessionStartDate(at url: URL) -> Date? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 2048)
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let firstLine = text.components(separatedBy: "\n").first(where: { !$0.isEmpty }) ?? ""
        guard let jsonData = firstLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let ts = json["timestamp"] as? String else { return nil }
        return iso8601.date(from: ts)
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
