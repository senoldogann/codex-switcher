import Foundation

/// ~/.codex/sessions/ dosyalarını parse ederek hesap başına token kullanımını hesaplar.
/// Attribution: switch history + activatedAt → hangi session hangi hesaba ait
final class SessionTokenParser {

    private let sessionsDir: URL
    private let iso8601: ISO8601DateFormatter

    init() {
        sessionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    /// profiles ve switch history'den hesap bazlı token kullanımını döner.
    func calculate(profiles: [Profile], history: [SwitchEvent]) -> [UUID: AccountTokenUsage] {
        // Zaman çizelgesi: [(activeFrom, accountId)]
        // En eskiden en yeniye sırala
        let timeline = buildTimeline(profiles: profiles, history: history)
        guard !timeline.isEmpty else { return [:] }

        var result: [UUID: AccountTokenUsage] = [:]

        let fm = FileManager.default
        guard let yearEnum = fm.enumerator(at: sessionsDir,
                                           includingPropertiesForKeys: [.isRegularFileKey],
                                           options: [.skipsHiddenFiles]) else { return [:] }

        for case let fileURL as URL in yearEnum {
            guard fileURL.pathExtension == "jsonl" else { continue }
            guard let sessionStart = sessionStartDate(at: fileURL) else { continue }
            guard let accountId = accountId(for: sessionStart, in: timeline) else { continue }

            let usage = finalTokenUsage(at: fileURL)
            guard usage.totalTokens > 0 else { continue }

            result[accountId] = (result[accountId] ?? AccountTokenUsage()) + usage
        }

        return result
    }

    // MARK: - Private

    /// [(activeFrom: Date, accountId: UUID)] en eski → en yeni
    private func buildTimeline(profiles: [Profile], history: [SwitchEvent]) -> [(Date, UUID)] {
        var points: [(Date, UUID)] = []

        // Her profil için activatedAt → başlangıç noktası
        for p in profiles {
            if let at = p.activatedAt {
                points.append((at, p.id))
            }
        }

        // Switch history'deki toAccountId + timestamp
        for event in history {
            points.append((event.timestamp, event.toAccountId))
        }

        // Tekrarlara göre temizle ve sırala
        let sorted = points.sorted { $0.0 < $1.0 }
        // Aynı hesabın ardışık tekrarlarını at
        var deduped: [(Date, UUID)] = []
        for point in sorted {
            if deduped.last?.1 != point.1 { deduped.append(point) }
        }
        return deduped
    }

    /// Belirli bir zaman için hangi hesabın aktif olduğunu bulur
    private func accountId(for date: Date, in timeline: [(Date, UUID)]) -> UUID? {
        // date'den önceki son noktayı bul
        var result: UUID? = nil
        for (from, id) in timeline {
            if from <= date { result = id }
            else { break }
        }
        return result
    }

    /// Session dosyasının ilk event'inin timestamp'ini döner
    private func sessionStartDate(at url: URL) -> Date? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 512)
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let firstLine = text.components(separatedBy: "\n").first ?? ""
        guard let json = try? JSONSerialization.jsonObject(with: Data(firstLine.utf8)) as? [String: Any],
              let ts = json["timestamp"] as? String else { return nil }
        return iso8601.date(from: ts)
    }

    /// Dosyadaki son token_count event'inin toplam kullanımını döner (cumulative)
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
