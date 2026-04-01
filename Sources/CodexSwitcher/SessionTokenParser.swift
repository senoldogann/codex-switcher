import Foundation

/// Her token_count event'inin hesaplanan delta değerini ve zaman damgasını tutar.
/// CodexBar'ın yaklaşımıyla aynı: kümülatif total'den delta hesapla, timestamp ile sakla.
struct SessionEventDelta: Codable {
    let timestamp: Date
    let model: String
    let inputDelta: Int
    let cachedDelta: Int
    let outputDelta: Int
}

/// ~/.codex/sessions/ dosyalarını parse eder.
/// - Her token_count event için önceki event'e göre delta hesaplar (CodexBar yaklaşımı)
/// - Her delta event'in kendi timestamp'iyle saklanır → doğru hesap attribution
/// - Yalnızca son 7 günün verileri gösterilir (haftalık billing penceresiyle uyumlu)
final class SessionTokenParser: @unchecked Sendable {

    private let sessionsDir: URL
    private let iso8601: ISO8601DateFormatter
    private let cacheDir: URL
    private let deltaCacheURL: URL
    private let modTimeCacheURL: URL

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
        deltaCacheURL = cacheDir.appendingPathComponent("event-deltas-v2.json")
        modTimeCacheURL = cacheDir.appendingPathComponent("token-usage.json.mod")
    }

    // MARK: - Public

    func calculate(profiles: [Profile], history: [SwitchEvent], activeProfileId: UUID? = nil) -> [UUID: AccountTokenUsage] {
        // Son 7 gün = haftalık billing penceresi
        let windowStart = Date().addingTimeInterval(-7 * 24 * 3600)

        // 1. Mevcut delta cache'i ve mod zamanlarını yükle
        var deltaCache = loadDeltaCache()
        let prevModTimes = loadFileModTimes()
        var newModTimes: [String: Date] = prevModTimes

        // 2. Değişen session dosyalarını tekrar parse et
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: sessionsDir,
                                              includingPropertiesForKeys: [.contentModificationDateKey],
                                              options: [.skipsHiddenFiles]) else {
            return attribute(deltaCache: deltaCache, windowStart: windowStart,
                             profiles: profiles, history: history, activeProfileId: activeProfileId)
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            newModTimes[url.path] = modDate

            let prev = prevModTimes[url.path]
            if prev == nil || prev != modDate {
                let deltas = parseEventDeltas(at: url, windowStart: windowStart)
                if deltas.isEmpty {
                    deltaCache.removeValue(forKey: url.path)
                } else {
                    deltaCache[url.path] = deltas
                }
            }
        }

        // Silinen dosyaları cache'den kaldır
        for path in prevModTimes.keys where newModTimes[path] == nil {
            newModTimes.removeValue(forKey: path)
            deltaCache.removeValue(forKey: path)
        }

        // 3. Cache'leri kaydet
        saveFileModTimes(newModTimes)
        saveDeltaCache(deltaCache)

        // 4. Delta'ları hesaplara attribute et
        return attribute(deltaCache: deltaCache, windowStart: windowStart,
                         profiles: profiles, history: history, activeProfileId: activeProfileId)
    }

    // MARK: - Attribution

    private func attribute(deltaCache: [String: [SessionEventDelta]],
                           windowStart: Date,
                           profiles: [Profile],
                           history: [SwitchEvent],
                           activeProfileId: UUID?) -> [UUID: AccountTokenUsage] {
        guard !deltaCache.isEmpty else { return [:] }

        // Son switch timestamp — bu tarihten sonraki event'ler aktif hesaba gider
        let lastSwitchTime = history.max(by: { $0.timestamp < $1.timestamp })?.timestamp

        var tokensByProfile: [UUID: AccountTokenUsage] = [:]
        var sessionsByProfile: [UUID: Set<String>] = [:]

        for (sessionPath, deltas) in deltaCache {
            for delta in deltas {
                // 7 günlük pencere dışındaki event'leri atla
                guard delta.timestamp > windowStart else { continue }

                let profileId: UUID?

                // Event timestamp'i son switch'ten sonraysa → aktif hesap
                // Aksi hâlde → event'in gerçekleştiği andaki aktif hesap
                if let activeProfileId = activeProfileId,
                   let lastSwitch = lastSwitchTime,
                   delta.timestamp > lastSwitch {
                    profileId = activeProfileId
                } else {
                    profileId = findActiveProfile(at: delta.timestamp,
                                                  profiles: profiles,
                                                  history: history)
                }

                guard let profileId = profileId else { continue }

                let usage = AccountTokenUsage(
                    inputTokens: delta.inputDelta,
                    cachedInputTokens: delta.cachedDelta,
                    outputTokens: delta.outputDelta,
                    reasoningTokens: 0,
                    sessionCount: 0,
                    modelUsage: [delta.model: ModelTokenUsage(
                        inputTokens: delta.inputDelta,
                        cachedInputTokens: delta.cachedDelta,
                        outputTokens: delta.outputDelta,
                        sessionCount: 0
                    )]
                )
                tokensByProfile[profileId, default: AccountTokenUsage()] =
                    tokensByProfile[profileId, default: AccountTokenUsage()] + usage
                sessionsByProfile[profileId, default: Set()].insert(sessionPath)
            }
        }

        // Session sayısını ekle
        var result: [UUID: AccountTokenUsage] = [:]
        for (profileId, usage) in tokensByProfile {
            let sessionCount = sessionsByProfile[profileId]?.count ?? 0
            result[profileId] = AccountTokenUsage(
                inputTokens: usage.inputTokens,
                cachedInputTokens: usage.cachedInputTokens,
                outputTokens: usage.outputTokens,
                reasoningTokens: usage.reasoningTokens,
                sessionCount: sessionCount,
                modelUsage: usage.modelUsage
            )
        }

        return result
    }

    private func findActiveProfile(at date: Date, profiles: [Profile], history: [SwitchEvent]) -> UUID? {
        let relevantSwitches = history.filter { $0.timestamp <= date }
        guard let lastSwitch = relevantSwitches.max(by: { $0.timestamp < $1.timestamp }) else {
            // No switch event recorded before this timestamp — don't guess.
            // Returning nil means tokens from before tracking starts are unattributed
            // (better than wrongly dumping them on whichever account happened to be "first").
            return nil
        }
        return lastSwitch.toAccountId
    }

    // MARK: - Session Parsing (CodexBar yaklaşımı: delta hesaplama)

    /// windowStart: all events are parsed (to build correct cumulative baseline),
    /// but only events AFTER windowStart are emitted as deltas.
    /// This prevents sessions that started before the window from counting all
    /// historical tokens as a single large delta on the first in-window event.
    private func parseEventDeltas(at url: URL, windowStart: Date) -> [SessionEventDelta] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var deltas: [SessionEventDelta] = []
        var prevInput = 0
        var prevCached = 0
        var prevOutput = 0
        var currentModel = "gpt-5"

        for line in content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty,
                  let data = t.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let type = json["type"] as? String

            // Model takibi (turn_context)
            if type == "turn_context" {
                if let payload = json["payload"] as? [String: Any] {
                    if let model = payload["model"] as? String {
                        currentModel = normalizeModel(model)
                    } else if let info = payload["info"] as? [String: Any],
                              let model = info["model"] as? String {
                        currentModel = normalizeModel(model)
                    }
                }
                continue
            }

            guard type == "event_msg",
                  let payload = json["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any]
            else { continue }

            // Event timestamp zorunlu — yoksa attribution yapılamaz
            guard let tsText = json["timestamp"] as? String,
                  let ts = parseDate(tsText) else { continue }

            // Model belirleme
            let modelFromInfo = info["model"] as? String ?? info["model_name"] as? String
            let modelFromPayload = payload["model"] as? String
            let modelFromRoot = json["model"] as? String
            let model = normalizeModel(modelFromInfo ?? modelFromPayload ?? modelFromRoot ?? currentModel)

            func toInt(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }

            if let total = info["total_token_usage"] as? [String: Any] {
                // Kümülatif total'den delta hesapla (CodexBar yaklaşımı).
                // prevInput her event için güncellenir (pencere öncesi eventler dahil)
                // böylece pencere başlangıcındaki baseline doğru hesaplanır.
                let curInput  = toInt(total["input_tokens"])
                let curCached = toInt(total["cached_input_tokens"] ?? total["cache_read_input_tokens"])
                let curOutput = toInt(total["output_tokens"])

                let dInput  = max(0, curInput  - prevInput)
                let dCached = max(0, curCached - prevCached)
                let dOutput = max(0, curOutput - prevOutput)

                prevInput  = curInput
                prevCached = curCached
                prevOutput = curOutput

                // Pencere dışındaki event'leri baseline için kullan ama kaydetme
                guard ts > windowStart else { continue }

                if dInput > 0 || dOutput > 0 {
                    deltas.append(SessionEventDelta(
                        timestamp: ts,
                        model: model,
                        inputDelta: dInput,
                        cachedDelta: min(dCached, dInput),
                        outputDelta: dOutput
                    ))
                }
            } else if let last = info["last_token_usage"] as? [String: Any] {
                // Fallback: event başına değerler (delta zaten verilmiş)
                guard ts > windowStart else { continue }

                let dInput  = max(0, toInt(last["input_tokens"]))
                let dCached = max(0, toInt(last["cached_input_tokens"] ?? last["cache_read_input_tokens"]))
                let dOutput = max(0, toInt(last["output_tokens"]))

                if dInput > 0 || dOutput > 0 {
                    deltas.append(SessionEventDelta(
                        timestamp: ts,
                        model: model,
                        inputDelta: dInput,
                        cachedDelta: min(dCached, dInput),
                        outputDelta: dOutput
                    ))
                }
            }
        }

        return deltas
    }

    // MARK: - Cache I/O

    private func loadDeltaCache() -> [String: [SessionEventDelta]] {
        guard let data = try? Data(contentsOf: deltaCacheURL),
              let dict = try? JSONDecoder().decode([String: [SessionEventDelta]].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func saveDeltaCache(_ cache: [String: [SessionEventDelta]]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: deltaCacheURL, options: .atomic)
    }

    private func loadFileModTimes() -> [String: Date] {
        guard let data = try? Data(contentsOf: modTimeCacheURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Double] else {
            return [:]
        }
        return dict.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private func saveFileModTimes(_ times: [String: Date]) {
        let dict = times.mapValues { $0.timeIntervalSince1970 }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? data.write(to: modTimeCacheURL, options: .atomic)
    }

    // MARK: - Date / Model Helpers

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

    private func normalizeModel(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("openai/") {
            trimmed = String(trimmed.dropFirst("openai/".count))
        }
        if let datedSuffix = trimmed.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            let base = String(trimmed[..<datedSuffix.lowerBound])
            let knownModels = ["gpt-5", "gpt-5-mini", "gpt-5-nano", "gpt-5-pro",
                               "gpt-5.1", "gpt-5.1-codex", "gpt-5.1-codex-max", "gpt-5.1-codex-mini",
                               "gpt-5.2", "gpt-5.2-codex", "gpt-5.2-pro",
                               "gpt-5.3-codex", "gpt-5.3-codex-spark",
                               "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano", "gpt-5.4-pro"]
            if knownModels.contains(base) { return base }
        }
        return trimmed
    }
}
