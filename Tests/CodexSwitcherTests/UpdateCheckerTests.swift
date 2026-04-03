import Foundation
import Testing
@testable import CodexSwitcher

struct UpdateCheckerTests {
    @Test
    func snapshotMarksUpToDateWhenVersionsMatch() throws {
        let data = Data("""
        {"tag_name":"v2.0.1","html_url":"https://github.com/senoldogann/codex-switcher/releases/tag/v2.0.1"}
        """.utf8)

        let snapshot = try #require(
            try UpdateChecker.snapshot(
                from: data,
                currentVersion: "2.0.1",
                checkedAt: Date(timeIntervalSince1970: 1)
            )
        )

        #expect(snapshot.state == .upToDate)
        #expect(snapshot.latestVersion == "2.0.1")
    }

    @Test
    func snapshotMarksUpdateAvailableWhenRemoteIsNewer() throws {
        let data = Data("""
        {"tag_name":"v2.0.2","html_url":"https://github.com/senoldogann/codex-switcher/releases/tag/v2.0.2"}
        """.utf8)

        let snapshot = try #require(
            try UpdateChecker.snapshot(
                from: data,
                currentVersion: "2.0.1",
                checkedAt: Date(timeIntervalSince1970: 1)
            )
        )

        #expect(snapshot.state == .updateAvailable)
        #expect(snapshot.release?.version == "2.0.2")
    }
}
