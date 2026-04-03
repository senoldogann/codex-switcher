import Foundation
import Testing
@testable import CodexSwitcher

struct AnalyticsRangeTests {
    @Test
    func calculateInsightsFiltersProjectsBySelectedRange() throws {
        let now = Date()
        let calendar = Calendar.current
        let oldDate = calendar.date(byAdding: .day, value: -45, to: now) ?? now
        let recentDate = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let formatter = ISO8601DateFormatter()

        let lines = [
            """
            {"timestamp":"\(formatter.string(from: oldDate))","type":"session_meta","payload":{"id":"old-session","cwd":"/tmp/old"}}
            """,
            """
            {"timestamp":"\(formatter.string(from: oldDate.addingTimeInterval(1)))","type":"event_msg","payload":{"type":"task_started"}}
            """,
            """
            {"timestamp":"\(formatter.string(from: oldDate.addingTimeInterval(2)))","type":"event_msg","payload":{"type":"user_message","message":"old prompt"}}
            """,
            """
            {"timestamp":"\(formatter.string(from: oldDate.addingTimeInterval(3)))","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":20}}}}
            """
        ]
        let recentLines = [
            """
            {"timestamp":"\(formatter.string(from: recentDate))","type":"session_meta","payload":{"id":"recent-session","cwd":"/tmp/recent"}}
            """,
            """
            {"timestamp":"\(formatter.string(from: recentDate.addingTimeInterval(1)))","type":"event_msg","payload":{"type":"task_started"}}
            """,
            """
            {"timestamp":"\(formatter.string(from: recentDate.addingTimeInterval(2)))","type":"event_msg","payload":{"type":"user_message","message":"recent prompt"}}
            """,
            """
            {"timestamp":"\(formatter.string(from: recentDate.addingTimeInterval(3)))","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":80,"output_tokens":10}}}}
            """
        ]

        let fixture = try SessionFixture.make(lines: lines, fileName: "old.jsonl")
        defer { fixture.cleanup() }
        try fixture.writeTestSession(lines: recentLines, fileName: "recent.jsonl")

        let parser = fixture.parser()
        let recentInsights = parser.calculateInsights(range: .sevenDays)
        let allInsights = parser.calculateInsights(range: .allTime)

        #expect(recentInsights.projects.map(\.name) == ["recent"])
        #expect(Set(allInsights.projects.map(\.name)) == Set(["old", "recent"]))
    }

    @Test
    func calculateDailyExpandsWindowForThirtyDays() throws {
        let now = Date()
        let calendar = Calendar.current
        let recent = calendar.date(byAdding: .day, value: -10, to: now) ?? now

        let formatter = ISO8601DateFormatter()
        let lines = [
            """
            {"timestamp":"\(formatter.string(from: recent))","type":"session_meta","payload":{"id":"session-30","cwd":"/tmp/demo"}}
            """,
            """
            {"timestamp":"\(formatter.string(from: recent.addingTimeInterval(1)))","type":"event_msg","payload":{"type":"task_started"}}
            """,
            """
            {"timestamp":"\(formatter.string(from: recent.addingTimeInterval(2)))","type":"event_msg","payload":{"type":"user_message","message":"within 30d"}}
            """,
            """
            {"timestamp":"\(formatter.string(from: recent.addingTimeInterval(3)))","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}
            """
        ]

        let fixture = try SessionFixture.make(lines: lines)
        defer { fixture.cleanup() }

        let parser = fixture.parser()
        let profiles = [Profile(alias: "Demo", email: "demo@example.com", accountId: "acct", addedAt: now)]
        let history = [
            SwitchEvent(
                id: UUID(),
                timestamp: calendar.date(byAdding: .day, value: -31, to: now) ?? now,
                fromAccountName: nil,
                fromAccountId: nil,
                toAccountName: "Demo",
                toAccountId: profiles[0].id,
                reason: "seed"
            )
        ]

        _ = parser.calculate(profiles: profiles, history: history, activeProfileId: profiles[0].id)

        let sevenDays = parser.calculateDaily(profiles: profiles, history: history, activeProfileId: profiles[0].id, range: .sevenDays)
        let thirtyDays = parser.calculateDaily(profiles: profiles, history: history, activeProfileId: profiles[0].id, range: .thirtyDays)

        #expect(sevenDays[profiles[0].id]?.allSatisfy { $0.tokens == 0 } == true)
        #expect(thirtyDays[profiles[0].id]?.contains(where: { $0.tokens == 110 }) == true)
    }

    @Test
    func calculateInsightsIncludesRecentTurnsFromOlderSessions() throws {
        let now = Date()
        let calendar = Calendar.current
        let sessionStart = calendar.date(byAdding: .day, value: -40, to: now) ?? now
        let recentTurn = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        let formatter = ISO8601DateFormatter()

        let lines = [
            """
            {"timestamp":"\(formatter.string(from: sessionStart))","type":"session_meta","payload":{"id":"long-session","cwd":"/tmp/long-lived"}}
            """,
            """
            {"timestamp":"\(formatter.string(from: recentTurn))","type":"event_msg","payload":{"type":"task_started"}}
            """,
            """
            {"timestamp":"\(formatter.string(from: recentTurn.addingTimeInterval(1)))","type":"event_msg","payload":{"type":"user_message","message":"recent work in old session"}}
            """,
            """
            {"timestamp":"\(formatter.string(from: recentTurn.addingTimeInterval(2)))","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":120,"output_tokens":30}}}}
            """
        ]

        let fixture = try SessionFixture.make(lines: lines)
        defer { fixture.cleanup() }

        let parser = fixture.parser()
        let insights = parser.calculateInsights(range: .sevenDays)

        #expect(insights.projects.map(\.name) == ["long-lived"])
        #expect(insights.expensiveTurns.count == 1)
        #expect(insights.sessions.first?.projectName == "long-lived")
    }
}
