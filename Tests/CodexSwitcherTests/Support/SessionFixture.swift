import Foundation
@testable import CodexSwitcher

struct SessionFixture {
    let rootDir: URL
    let sessionsDir: URL
    let cacheDir: URL

    static func make(lines: [String], fileName: String = "session-1.jsonl") throws -> SessionFixture {
        let fm = FileManager.default
        let rootDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDir = rootDir.appendingPathComponent("sessions", isDirectory: true)
        let cacheDir = rootDir.appendingPathComponent("cache", isDirectory: true)

        try fm.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let fixture = SessionFixture(rootDir: rootDir, sessionsDir: sessionsDir, cacheDir: cacheDir)
        try fixture.writeSession(lines: lines, fileName: fileName)
        return fixture
    }

    func parser() -> SessionTokenParser {
        SessionTokenParser(sessionsDir: sessionsDir, cacheBaseDir: cacheDir)
    }

    func writeTestSession(lines: [String], fileName: String) throws {
        try writeSession(lines: lines, fileName: fileName)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDir)
    }

    private func writeSession(lines: [String], fileName: String) throws {
        let content = lines.joined(separator: "\n") + "\n"
        let sessionURL = sessionsDir.appendingPathComponent(fileName)
        try content.write(to: sessionURL, atomically: true, encoding: .utf8)
    }
}
