import Foundation

/// Switch geçmişini ~/.codex-switcher/switch-history.json dosyasına kaydeder.
final class SwitchHistoryStore {

    private let url: URL
    private let maxEvents = 50
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-switcher")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("switch-history.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [SwitchEvent] {
        guard let data = try? Data(contentsOf: url),
              let events = try? decoder.decode([SwitchEvent].self, from: data) else { return [] }
        return events
    }

    func append(_ event: SwitchEvent) {
        var events = load()
        events.append(event)
        if events.count > maxEvents { events = Array(events.suffix(maxEvents)) }
        try? encoder.encode(events).write(to: url)
    }
}
