import Foundation

final class SwitchTimelineStore {
    private let url: URL
    private let maxEvents = 500
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-switcher")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("switch-timeline.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [SwitchTimelineEvent] {
        guard let data = try? Data(contentsOf: url),
              let events = try? decoder.decode([SwitchTimelineEvent].self, from: data) else { return [] }
        return events
    }

    func append(_ event: SwitchTimelineEvent) {
        var events = load()
        events.append(event)
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
        try? encoder.encode(events).write(to: url)
    }
}
