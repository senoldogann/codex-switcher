import Foundation
import Testing
@testable import CodexSwitcher

struct SwitchDecisionStoreTests {
    @Test
    func loadReturnsEmptyArrayWhenStoreIsMissing() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let store = SwitchDecisionStore(baseDirectory: baseDirectory)

        #expect(store.load().isEmpty)
    }

    @Test
    func appendAndLoadRoundTripDecisionRecords() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let store = SwitchDecisionStore(baseDirectory: baseDirectory)
        let record = SwitchDecisionRecord(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            source: .automatic,
            outcome: .queued,
            requestedProfileId: nil,
            requestedProfileName: nil,
            chosenProfileId: UUID(),
            chosenProfileName: "Account 2",
            reason: "Limit reached",
            detail: "Switch was queued.",
            overrideApplied: false,
            readiness: []
        )

        store.append(record)

        #expect(store.load() == [record])
    }

    @Test
    func appendKeepsOnlyNewestBoundedRecords() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let store = SwitchDecisionStore(baseDirectory: baseDirectory, maxEvents: 2)
        let first = makeRecord(timestamp: 1, name: "First")
        let second = makeRecord(timestamp: 2, name: "Second")
        let third = makeRecord(timestamp: 3, name: "Third")

        store.append(first)
        store.append(second)
        store.append(third)

        #expect(store.load().map(\.chosenProfileName) == ["Second", "Third"])
    }

    private func makeRecord(timestamp: TimeInterval, name: String) -> SwitchDecisionRecord {
        SwitchDecisionRecord(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: timestamp),
            source: .manual,
            outcome: .executed,
            requestedProfileId: UUID(),
            requestedProfileName: name,
            chosenProfileId: UUID(),
            chosenProfileName: name,
            reason: "Manual selection",
            detail: "Executed",
            overrideApplied: false,
            readiness: []
        )
    }
}
