import Foundation

/// ~/.codex/sessions/ klasörünü izler; rate limit hatası algılandığında onRateLimit çağrılır.
@preconcurrency final class UsageMonitor: @unchecked Sendable {

    var onRateLimit: (() -> Void)?

    private var sessionsDirSource: DispatchSourceFileSystemObject?
    private var fileWatchers: [String: DispatchSourceFileSystemObject] = [:]
    private var fileTails: [String: Int64] = [:]
    private let queue = DispatchQueue(label: "codex.switcher.usage", qos: .utility)

    private let sessionsDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
    }()

    // Rate limit göstergesi olan anahtar kelimeler (OpenAI/Codex hata mesajları)
    private let rateLimitKeywords: [String] = [
        "rate_limit", "rate_limited", "quota_exceeded",
        "usage_limit", "usage_exceeded", "limit_exceeded",
        "too_many_requests", "insufficient_quota",
        "wham_limit", "limit_reached", "context_length_exceeded",
        "you've reached your", "you have reached your",
        "usage limit", "codex limit"
    ]

    // MARK: - Lifecycle

    func start() {
        watchSessionsDirectory()
        watchExistingSessionFiles()
    }

    func stop() {
        sessionsDirSource?.cancel()
        fileWatchers.values.forEach { $0.cancel() }
        fileWatchers.removeAll()
        fileTails.removeAll()
    }

    // MARK: - Directory Watcher

    private func watchSessionsDirectory() {
        guard FileManager.default.fileExists(atPath: sessionsDir.path) else { return }

        let fd = open(sessionsDir.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .link],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.watchExistingSessionFiles()
        }

        source.setCancelHandler { close(fd) }
        source.resume()
        sessionsDirSource = source
    }

    // MARK: - File Watchers

    private func watchExistingSessionFiles() {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let path = url.path
            if fileWatchers[path] == nil {
                watchFile(at: path)
            }
        }
    }

    private func watchFile(at path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        // Mevcut dosya boyutunu kaydet — sadece yeni satırları okuyacağız
        let currentSize = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64 ?? 0
        fileTails[path] = currentSize

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.readNewLines(from: path)
        }

        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatchers[path] = source
    }

    // MARK: - Line Parser

    private func readNewLines(from path: String) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }

        let offset = fileTails[path] ?? 0
        try? handle.seek(toOffset: UInt64(offset))
        let newData = handle.readDataToEndOfFile()

        // Yeni offset kaydet
        fileTails[path] = offset + Int64(newData.count)

        guard let text = String(data: newData, encoding: .utf8) else { return }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            checkForRateLimit(in: trimmed)
        }
    }

    private func checkForRateLimit(in jsonLine: String) {
        // Hızlı string arama — JSON parse'tan önce
        let lower = jsonLine.lowercased()
        let hasKeyword = rateLimitKeywords.contains { lower.contains($0) }
        let has429 = lower.contains("429") || lower.contains("\"status_code\":429")

        guard hasKeyword || has429 else { return }

        // JSON parse ile doğrula
        guard let data = jsonLine.data(using: .utf8),
              let event = try? JSONDecoder().decode(SessionEvent.self, from: data) else {
            // JSON parse başarısız olsa bile keyword eşleşti — tetikle
            if hasKeyword || has429 { triggerSwitch() }
            return
        }

        let isError = isRateLimitEvent(event)
        if isError { triggerSwitch() }
    }

    private func isRateLimitEvent(_ event: SessionEvent) -> Bool {
        // event_msg tipi kontrolü
        if event.type == "event_msg" {
            if let payloadType = event.payload.type {
                let lower = payloadType.lowercased()
                if rateLimitKeywords.contains(where: { lower.contains($0) }) { return true }
            }
            if let statusCode = event.payload.statusCode, statusCode == 429 { return true }
            if let error = event.payload.error {
                let texts = [error.code, error.type, error.message].compactMap { $0 }
                return texts.contains { text in
                    rateLimitKeywords.contains { text.lowercased().contains($0) }
                }
            }
        }

        // response_item tipi — error içerik kontrolü
        if event.type == "response_item" {
            if let statusCode = event.payload.statusCode, statusCode == 429 { return true }
        }

        return false
    }

    private func triggerSwitch() {
        DispatchQueue.main.async { [weak self] in
            self?.onRateLimit?()
        }
    }
}
