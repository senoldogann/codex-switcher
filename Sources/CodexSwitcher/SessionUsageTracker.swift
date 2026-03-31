import Foundation

/// ~/.codex/sessions/ dosyalarından belirtilen tarihten bu yana task_started sayısını okur.
final class SessionUsageTracker {

    private let sessionsDir: URL
    private let iso8601: ISO8601DateFormatter

    init() {
        sessionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    /// Verilen tarihten bu yana kaç task başlatıldı (hesap bazlı takip için)
    func turnsSince(_ date: Date) -> Int {
        let calendar = Calendar.current
        let now = Date()
        var count = 0

        // Başlangıç tarihi ile bugün arasındaki günleri tara
        var current = date
        while current <= now {
            let year  = calendar.component(.year,  from: current)
            let month = calendar.component(.month, from: current)
            let day   = calendar.component(.day,   from: current)

            let dir = sessionsDir
                .appendingPathComponent(String(year))
                .appendingPathComponent(String(format: "%02d", month))
                .appendingPathComponent(String(format: "%02d", day))

            if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                for file in files where file.hasSuffix(".jsonl") {
                    count += countTasksStarted(in: dir.appendingPathComponent(file), since: date)
                }
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return count
    }

    /// Son 5 saatteki tüm task sayısı (aktif hesap için gerçek zamanlı)
    func turnsInLast(hours: Double = 5) -> Int {
        turnsSince(Date().addingTimeInterval(-hours * 3600))
    }

    private func countTasksStarted(in url: URL, since cutoff: Date) -> Int {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        var count = 0
        for line in content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty,
                  let data = t.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["type"] as? String == "event_msg",
                  let payload = json["payload"] as? [String: Any],
                  payload["type"] as? String == "task_started",
                  let ts = json["timestamp"] as? String,
                  let eventDate = iso8601.date(from: ts),
                  eventDate >= cutoff
            else { continue }
            count += 1
        }
        return count
    }
}
