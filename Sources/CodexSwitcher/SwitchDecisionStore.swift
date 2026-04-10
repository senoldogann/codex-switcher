import Foundation

final class SwitchDecisionStore {
    private let url: URL
    private let maxEvents: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseDirectory: URL? = nil, maxEvents: Int = 500) {
        let base = baseDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-switcher")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("switch-decisions.json")
        self.maxEvents = maxEvents
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [SwitchDecisionRecord] {
        guard let data = try? Data(contentsOf: url),
              let events = try? decoder.decode([SwitchDecisionRecord].self, from: data) else { return [] }
        return events
    }

    func append(_ event: SwitchDecisionRecord) {
        var events = load()
        events.append(event)
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
        try? encoder.encode(events).write(to: url)
    }
}
