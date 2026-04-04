import Foundation
import Testing
@testable import CodexSwitcher

struct SessionUsageTrackerTests {
    @Test
    func turnsSinceReusesCachedParseForUnchangedSessionFiles() throws {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: now.addingTimeInterval(-60))

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dayDir = root
            .appendingPathComponent(String(Calendar.current.component(.year, from: now)))
            .appendingPathComponent(String(format: "%02d", Calendar.current.component(.month, from: now)))
            .appendingPathComponent(String(format: "%02d", Calendar.current.component(.day, from: now)))
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        let sessionFile = dayDir.appendingPathComponent("session.jsonl")
        try """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"task_started"}}

        """.write(to: sessionFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        final class CountingReader: @unchecked Sendable {
            var readCount = 0

            func read(_ url: URL) -> String? {
                readCount += 1
                return try? String(contentsOf: url, encoding: .utf8)
            }
        }

        let reader = CountingReader()
        let tracker = SessionUsageTracker(
            sessionsDir: root,
            sessionFileReader: { reader.read($0) }
        )

        let firstCount = tracker.turnsSince(now.addingTimeInterval(-3600))
        let secondCount = tracker.turnsSince(now.addingTimeInterval(-3600))

        #expect(firstCount == 1)
        #expect(secondCount == 1)
        #expect(reader.readCount == 1)
    }
}
