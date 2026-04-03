import Foundation
import Testing
@testable import CodexSwitcher

struct SwitchTimelineStoreTests {
    @Test
    func appendAndLoadRoundTripsTimelineEvents() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let store = SwitchTimelineStore(baseDirectory: baseDirectory)
        let event = SwitchTimelineEvent(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_700_001_000),
            stage: .queued,
            targetProfileName: "Account 2",
            reason: "Limit reached",
            detail: "Switch was deferred until the active work finished.",
            waitDurationSeconds: nil,
            verificationDurationSeconds: nil
        )

        store.append(event)

        let loaded = store.load()
        #expect(loaded == [event])
    }
}
