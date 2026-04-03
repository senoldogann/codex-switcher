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
    private let sessionMetaCacheURL: URL
    private let sessionModTimeCacheURL: URL

    // MARK: - Internal session meta cache types

    fileprivate struct SessionFileMeta: Codable {
        let sessionId: String
        let cwd: String
        let firstPrompt: String
        let startTime: Double          // timeIntervalSince1970
        let depth: Int
        let agentRole: String
        let parentId: String?
        let turns: [CachedTurn]

        var totalTokens: Int { turns.reduce(0) { $0 + $1.inputTokens + $1.outputTokens } }

        struct CachedTurn: Codable {
            let promptPreview: String
            let inputTokens: Int
            let cachedInputTokens: Int
            let outputTokens: Int
            let timestamp: Double      // timeIntervalSince1970
            let model: String

            /// Total tokens for display/sorting
            var tokens: Int { inputTokens + outputTokens }
        }
    }

    private struct FilteredSessionMeta {
        let sessionId: String
        let cwd: String
        let firstPrompt: String
        let depth: Int
        let agentRole: String
        let parentId: String?
        let turns: [SessionFileMeta.CachedTurn]

        var totalTokens: Int {
            turns.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
        }

        var lastActivityTimestamp: Double {
            turns.map(\.timestamp).max() ?? 0
        }
    }

    private struct PendingTurn {
        let promptPreview: String
        let timestamp: Double
        var inputTokens: Int
        var cachedInputTokens: Int
        var outputTokens: Int
        var model: String

        var hasTokens: Bool { inputTokens > 0 || outputTokens > 0 }
    }

    init(sessionsDir: URL? = nil, cacheBaseDir: URL? = nil) {
        self.sessionsDir = sessionsDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let base = cacheBaseDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-switcher")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        cacheDir = base.appendingPathComponent("cache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        deltaCacheURL = cacheDir.appendingPathComponent("event-deltas-v2.json")
        modTimeCacheURL = cacheDir.appendingPathComponent("token-usage.json.mod")
        sessionMetaCacheURL = cacheDir.appendingPathComponent("session-meta-v3.json")
        sessionModTimeCacheURL = cacheDir.appendingPathComponent("session-meta-v3.mod")
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
                let deltas = parseEventDeltas(at: url)
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

    /// Parse all token deltas so higher-level callers can apply their own time windows.
    private func parseEventDeltas(at url: URL) -> [SessionEventDelta] {
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

    // MARK: - Daily Aggregation (for 7-day chart)

    /// Groups cached deltas into per-day, per-account token totals.
    /// Reuses the delta cache written by calculate() so no extra file parsing.
    func calculateDaily(profiles: [Profile], history: [SwitchEvent], activeProfileId: UUID?, range: AnalyticsTimeRange = .sevenDays) -> [UUID: [DailyUsage]] {
        let windowStart = cutoffDate(for: range)
        let deltaCache = loadDeltaCache()
        guard !deltaCache.isEmpty else { return [:] }

        let calendar = Calendar.current
        let lastSwitchTime = history.max(by: { $0.timestamp < $1.timestamp })?.timestamp
        var dailyTokens: [UUID: [Date: Int]] = [:]

        for (_, deltas) in deltaCache {
            for delta in deltas {
                if let windowStart, delta.timestamp <= windowStart { continue }

                let profileId: UUID?
                if let activeProfileId,
                   let lastSwitch = lastSwitchTime,
                   delta.timestamp > lastSwitch {
                    profileId = activeProfileId
                } else {
                    profileId = findActiveProfile(at: delta.timestamp, profiles: profiles, history: history)
                }
                guard let pid = profileId else { continue }

                let day = calendar.startOfDay(for: delta.timestamp)
                let tokens = delta.inputDelta + delta.outputDelta
                dailyTokens[pid, default: [:]][day, default: 0] += tokens
            }
        }

        // Build full range array for each profile (zero for missing days)
        let today = calendar.startOfDay(for: Date())
        let startDay: Date = {
            if let windowStart {
                return calendar.startOfDay(for: windowStart)
            }
            let allDays = dailyTokens.values.flatMap { $0.keys }
            return allDays.min().map { calendar.startOfDay(for: $0) } ?? today
        }()
        var result: [UUID: [DailyUsage]] = [:]
        for profile in profiles {
            let dayData = dailyTokens[profile.id] ?? [:]
            var days: [DailyUsage] = []
            var day = startDay
            while day <= today {
                days.append(DailyUsage(dayStart: day, tokens: dayData[day] ?? 0))
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
            }
            result[profile.id] = days
        }
        return result
    }

    func calculateAnalyticsRecords(
        profiles: [Profile],
        history: [SwitchEvent],
        activeProfileId: UUID?
    ) -> [AnalyticsUsageRecord] {
        let deltaCache = loadDeltaCache()
        let metaCache = refreshSessionMetaCache()
        guard !deltaCache.isEmpty else { return [] }

        let lastSwitchTime = history.max(by: { $0.timestamp < $1.timestamp })?.timestamp
        var records: [AnalyticsUsageRecord] = []

        for (sessionPath, deltas) in deltaCache {
            let meta = metaCache[sessionPath]
            let projectPath = meta?.cwd.isEmpty == false ? meta?.cwd : nil
            let resolvedProjectPath = projectPath ?? "unknown"
            let projectName = resolvedProjectPath == "unknown"
                ? L("Bilinmiyor", "Unknown")
                : URL(fileURLWithPath: resolvedProjectPath).lastPathComponent
            let sessionId = meta?.sessionId ?? URL(fileURLWithPath: sessionPath).lastPathComponent

            for delta in deltas {
                let profileId: UUID?
                if let activeProfileId,
                   let lastSwitch = lastSwitchTime,
                   delta.timestamp > lastSwitch {
                    profileId = activeProfileId
                } else {
                    profileId = findActiveProfile(at: delta.timestamp, profiles: profiles, history: history)
                }

                guard let profileId else { continue }

                records.append(
                    AnalyticsUsageRecord(
                        timestamp: delta.timestamp,
                        profileId: profileId,
                        projectPath: resolvedProjectPath,
                        projectName: projectName,
                        sessionId: sessionId,
                        model: delta.model,
                        inputTokens: delta.inputDelta,
                        cachedInputTokens: delta.cachedDelta,
                        outputTokens: delta.outputDelta
                    )
                )
            }
        }

        return records.sorted { $0.timestamp < $1.timestamp }
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

    func calculateSessionRecords(range: AnalyticsTimeRange = .allTime) -> [AnalyticsSessionRecord] {
        let metaCache = refreshSessionMetaCache()
        guard !metaCache.isEmpty else { return [] }

        let cutoff = cutoffDate(for: range)
        return metaCache.values.compactMap { meta in
            let filteredTurns = meta.turns.filter { turn in
                guard let cutoff else { return true }
                return Date(timeIntervalSince1970: turn.timestamp) > cutoff
            }
            guard !filteredTurns.isEmpty else { return nil }

            let projectPath = meta.cwd.isEmpty ? "unknown" : meta.cwd
            let projectName = projectPath == "unknown" ? L("Bilinmiyor", "Unknown") : URL(fileURLWithPath: projectPath).lastPathComponent

            return AnalyticsSessionRecord(
                sessionId: meta.sessionId.isEmpty ? UUID().uuidString : meta.sessionId,
                projectPath: projectPath,
                projectName: projectName,
                firstPrompt: meta.firstPrompt,
                depth: meta.depth,
                agentRole: meta.agentRole,
                parentId: meta.parentId,
                turns: filteredTurns.map { turn in
                    AnalyticsSessionTurnRecord(
                        promptPreview: turn.promptPreview,
                        inputTokens: turn.inputTokens,
                        cachedInputTokens: turn.cachedInputTokens,
                        outputTokens: turn.outputTokens,
                        timestamp: Date(timeIntervalSince1970: turn.timestamp),
                        model: turn.model
                    )
                }
            )
        }
        .sorted { $0.lastActivity > $1.lastActivity }
    }

    private func cutoffDate(for range: AnalyticsTimeRange) -> Date? {
        range.cutoffDate(from: Date())
    }

    // MARK: - Session Meta Cache

    private func refreshSessionMetaCache() -> [String: SessionFileMeta] {
        var metaCache = loadSessionMetaCache()
        let prevModTimes = loadSessionModTimes()
        var newModTimes: [String: Date] = prevModTimes

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: sessionsDir,
                                              includingPropertiesForKeys: [.contentModificationDateKey],
                                              options: [.skipsHiddenFiles]) else {
            return metaCache
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date.distantPast
            newModTimes[url.path] = modDate

            if prevModTimes[url.path] == nil || prevModTimes[url.path] != modDate {
                if let parsed = parseSessionFileMeta(at: url) {
                    metaCache[url.path] = parsed
                } else {
                    metaCache.removeValue(forKey: url.path)
                }
            }
        }

        for path in prevModTimes.keys where newModTimes[path] == nil {
            newModTimes.removeValue(forKey: path)
            metaCache.removeValue(forKey: path)
        }

        saveSessionMetaCache(metaCache)
        saveSessionModTimes(newModTimes)
        return metaCache
    }

    private func parseSessionFileMeta(at url: URL) -> SessionFileMeta? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var sessionId  = ""
        var cwd        = ""
        var depth      = 0
        var agentRole  = "default"
        var parentId: String? = nil
        var startTime: Double = 0
        var firstPrompt = ""
        var currentTurnPrompt = ""
        var currentTurnModel  = "gpt-5"
        var currentTurnTs: Double = 0
        var prevInput  = 0
        var prevCached = 0
        var prevOutput = 0
        var turns: [SessionFileMeta.CachedTurn] = []
        var pendingTurn: PendingTurn?
        var sessionMetaParsed = false

        func toInt(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? (v as? Int) ?? 0 }
        func flushPendingTurn() {
            guard let turn = pendingTurn, turn.hasTokens else {
                pendingTurn = nil
                return
            }

            turns.append(SessionFileMeta.CachedTurn(
                promptPreview: turn.promptPreview,
                inputTokens: turn.inputTokens,
                cachedInputTokens: min(turn.cachedInputTokens, turn.inputTokens),
                outputTokens: turn.outputTokens,
                timestamp: turn.timestamp,
                model: turn.model
            ))
            pendingTurn = nil
        }

        for line in content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty,
                  let data = t.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let type = json["type"] as? String
            let tsStr = json["timestamp"] as? String
            let tsDate = tsStr.flatMap { parseDate($0) }
            let ts = tsDate?.timeIntervalSince1970 ?? 0

            // ── session_meta ─────────────────────────────────────────────
            if type == "session_meta", !sessionMetaParsed {
                sessionMetaParsed = true
                if let payload = json["payload"] as? [String: Any] {
                    sessionId = payload["id"] as? String ?? ""
                    cwd = payload["cwd"] as? String ?? ""
                    startTime = ts > 0 ? ts : {
                        if let tsPayload = payload["timestamp"] as? String,
                           let d = parseDate(tsPayload) { return d.timeIntervalSince1970 }
                        return 0
                    }()
                    agentRole = payload["agent_role"] as? String ?? "default"
                    if let src = payload["source"] as? [String: Any],
                       let sa  = src["subagent"] as? [String: Any],
                       let spawn = sa["thread_spawn"] as? [String: Any] {
                        parentId = spawn["parent_thread_id"] as? String
                        depth    = toInt(spawn["depth"])
                        if agentRole == "default" {
                            agentRole = spawn["agent_role"] as? String ?? "default"
                        }
                    }
                }
                continue
            }

            // ── turn_context: model update ─────────────────────────────
            if type == "turn_context" {
                if let payload = json["payload"] as? [String: Any],
                   let model = payload["model"] as? String
                    ?? (payload["info"] as? [String: Any])?["model"] as? String {
                    currentTurnModel = normalizeModel(model)
                }
                continue
            }

            guard type == "event_msg",
                  let payload = json["payload"] as? [String: Any]
            else { continue }

            let payloadType = payload["type"] as? String

            // ── task_started: new turn ──────────────────────────────────
            if payloadType == "task_started" {
                flushPendingTurn()
                currentTurnPrompt = ""
                currentTurnTs = ts
                continue
            }

            // ── user_message: capture prompt ────────────────────────────
            if payloadType == "user_message" {
                flushPendingTurn()
                if let msg = payload["message"] as? String {
                    let trimmed = msg
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .components(separatedBy: "\n").first ?? ""
                    let preview = String(trimmed.prefix(120))
                    if firstPrompt.isEmpty { firstPrompt = preview }
                    currentTurnPrompt = preview
                }
                continue
            }

            // ── token_count: compute per-turn delta ─────────────────────
            if payloadType == "token_count",
               let info = payload["info"] as? [String: Any] {
                let modelFromInfo = info["model"] as? String ?? info["model_name"] as? String
                let modelFromPayload = payload["model"] as? String
                let modelFromRoot = json["model"] as? String
                if let model = modelFromInfo ?? modelFromPayload ?? modelFromRoot {
                    currentTurnModel = normalizeModel(model)
                }

                var dInput = 0
                var dCached = 0
                var dOutput = 0

                if let total = info["total_token_usage"] as? [String: Any] {
                    let curInput  = toInt(total["input_tokens"])
                    let curCached = toInt(total["cached_input_tokens"] ?? total["cache_read_input_tokens"])
                    let curOutput = toInt(total["output_tokens"])
                    dInput  = max(0, curInput  - prevInput)
                    dCached = max(0, curCached - prevCached)
                    dOutput = max(0, curOutput - prevOutput)
                    prevInput  = curInput
                    prevCached = curCached
                    prevOutput = curOutput
                } else if let last = info["last_token_usage"] as? [String: Any] {
                    dInput  = max(0, toInt(last["input_tokens"]))
                    dCached = max(0, toInt(last["cached_input_tokens"] ?? last["cache_read_input_tokens"]))
                    dOutput = max(0, toInt(last["output_tokens"]))
                }

                if dInput + dOutput > 0, !currentTurnPrompt.isEmpty {
                    if pendingTurn == nil {
                        pendingTurn = PendingTurn(
                            promptPreview: currentTurnPrompt,
                            timestamp: currentTurnTs > 0 ? currentTurnTs : ts,
                            inputTokens: 0,
                            cachedInputTokens: 0,
                            outputTokens: 0,
                            model: currentTurnModel
                        )
                    }
                    if var turn = pendingTurn {
                        turn.inputTokens += dInput
                        turn.cachedInputTokens += dCached
                        turn.outputTokens += dOutput
                        turn.model = currentTurnModel
                        pendingTurn = turn
                    }
                }
            }
        }

        flushPendingTurn()

        guard !sessionId.isEmpty || startTime > 0 else { return nil }
        return SessionFileMeta(
            sessionId: sessionId,
            cwd: cwd,
            firstPrompt: firstPrompt,
            startTime: startTime,
            depth: depth,
            agentRole: agentRole,
            parentId: parentId,
            turns: turns)
    }

    private func loadSessionMetaCache() -> [String: SessionFileMeta] {
        guard let data = try? Data(contentsOf: sessionMetaCacheURL),
              let dict = try? JSONDecoder().decode([String: SessionFileMeta].self, from: data)
        else { return [:] }
        return dict
    }

    private func saveSessionMetaCache(_ cache: [String: SessionFileMeta]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: sessionMetaCacheURL, options: .atomic)
    }

    private func loadSessionModTimes() -> [String: Date] {
        guard let data = try? Data(contentsOf: sessionModTimeCacheURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Double]
        else { return [:] }
        return dict.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private func saveSessionModTimes(_ times: [String: Date]) {
        let dict = times.mapValues { $0.timeIntervalSince1970 }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? data.write(to: sessionModTimeCacheURL, options: .atomic)
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
        ModelPricing.normalizeModel(raw)
    }
}
