import Foundation
import Testing
@testable import CodexSwitcher

struct TopDollarInsightsTests {
    @Test
    func insightsSortExpensiveTurnsByTrueCostIncludingCachedInputTokens() throws {
        let fixture = try TopDollarFixture.make()
        defer { fixture.cleanup() }

        let parser = fixture.parser()
        let insights = parser.calculateInsights()

        #expect(insights.expensiveTurns.count == 2)
        #expect(insights.expensiveTurns.map(\.promptPreview) == ["mini turn", "cached-heavy turn"])
        #expect(insights.expensiveTurns[0].cost > insights.expensiveTurns[1].cost)
    }

    @Test
    func projectCostsIncludeCachedInputDiscount() throws {
        let fixture = try TopDollarFixture.make()
        defer { fixture.cleanup() }

        let parser = fixture.parser()
        let insights = parser.calculateInsights()

        let expected = CostCalculator().cost(
            for: AccountTokenUsage(
                inputTokens: 3_000,
                cachedInputTokens: 900,
                outputTokens: 110,
                reasoningTokens: 0,
                sessionCount: 0,
                modelUsage: [
                    "gpt-5": ModelTokenUsage(
                        inputTokens: 1_000,
                        cachedInputTokens: 900,
                        outputTokens: 10,
                        sessionCount: 0
                    ),
                    "gpt-5-mini": ModelTokenUsage(
                        inputTokens: 2_000,
                        cachedInputTokens: 0,
                        outputTokens: 100,
                        sessionCount: 0
                    )
                ]
            )
        )

        let project = try #require(insights.projects.first)
        #expect(abs(project.cost - expected) < 0.000_000_1)
    }

    @Test
    func topDollarPresentationUsesCostForBarsAndShowsPreciseSmallCosts() {
        let expensive = ExpensiveTurn(
            id: "high-cost",
            projectName: "Demo",
            promptPreview: "high-cost prompt",
            inputTokens: 80,
            outputTokens: 20,
            cost: 0.0007,
            timestamp: .distantPast,
            model: "gpt-5"
        )
        let cheap = ExpensiveTurn(
            id: "low-cost",
            projectName: "Demo",
            promptPreview: "low-cost prompt",
            inputTokens: 2_000,
            outputTokens: 500,
            cost: 0.00035,
            timestamp: .distantPast,
            model: "gpt-5-mini"
        )

        let metrics = ExpensiveTurnMetrics(turns: [expensive, cheap])

        #expect(metrics.costFraction(for: expensive) == 1)
        #expect(metrics.costFraction(for: cheap) == 0.5)
        #expect(ExpensiveTurnMetrics.formatCost(expensive.cost) == "$0.0007")
    }

    @Test
    func insightsReadModelAndCacheReadTokensFromTotalUsagePayload() throws {
        let lines = [
            """
            {"timestamp":"2026-04-03T11:00:00Z","type":"session_meta","payload":{"id":"session-2","cwd":"/tmp/demo"}}
            """,
            """
            {"timestamp":"2026-04-03T11:00:01Z","type":"event_msg","payload":{"type":"task_started"}}
            """,
            """
            {"timestamp":"2026-04-03T11:00:02Z","type":"event_msg","payload":{"type":"user_message","message":"model in payload"}}
            """,
            """
            {"timestamp":"2026-04-03T11:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"model_name":"gpt-5-mini","total_token_usage":{"input_tokens":1000,"cache_read_input_tokens":800,"output_tokens":100}}}}
            """
        ]

        let fixture = try TopDollarFixture.make(lines: lines)
        defer { fixture.cleanup() }

        let parser = fixture.parser()
        let insights = parser.calculateInsights()

        let turn = try #require(insights.expensiveTurns.first)
        let expected = CostCalculator().cost(
            for: AccountTokenUsage(
                inputTokens: 1_000,
                cachedInputTokens: 800,
                outputTokens: 100,
                reasoningTokens: 0,
                sessionCount: 0,
                modelUsage: [
                    "gpt-5-mini": ModelTokenUsage(
                        inputTokens: 1_000,
                        cachedInputTokens: 800,
                        outputTokens: 100,
                        sessionCount: 0
                    )
                ]
            )
        )

        #expect(turn.model == "gpt-5-mini")
        #expect(abs(turn.cost - expected) < 0.000_000_1)
    }

    @Test
    func insightsNormalizeDatedModelNamesFromTokenPayload() throws {
        let lines = [
            """
            {"timestamp":"2026-04-03T12:00:00Z","type":"session_meta","payload":{"id":"session-3","cwd":"/tmp/demo"}}
            """,
            """
            {"timestamp":"2026-04-03T12:00:01Z","type":"event_msg","payload":{"type":"task_started"}}
            """,
            """
            {"timestamp":"2026-04-03T12:00:02Z","type":"event_msg","payload":{"type":"user_message","message":"dated model"}}
            """,
            """
            {"timestamp":"2026-04-03T12:00:03Z","type":"event_msg","payload":{"type":"token_count","model":"openai/gpt-5-codex-2025-01-15","info":{"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}
            """
        ]

        let fixture = try TopDollarFixture.make(lines: lines)
        defer { fixture.cleanup() }

        let parser = fixture.parser()
        let insights = parser.calculateInsights()

        let turn = try #require(insights.expensiveTurns.first)
        #expect(turn.model == "gpt-5-codex")
    }

    @Test
    func insightsReadModelFromTurnContextInfoPayload() throws {
        let lines = [
            """
            {"timestamp":"2026-04-03T13:00:00Z","type":"session_meta","payload":{"id":"session-4","cwd":"/tmp/demo"}}
            """,
            """
            {"timestamp":"2026-04-03T13:00:01Z","type":"turn_context","payload":{"info":{"model":"gpt-5.4-mini"}}}
            """,
            """
            {"timestamp":"2026-04-03T13:00:02Z","type":"event_msg","payload":{"type":"task_started"}}
            """,
            """
            {"timestamp":"2026-04-03T13:00:03Z","type":"event_msg","payload":{"type":"user_message","message":"context model"}}
            """,
            """
            {"timestamp":"2026-04-03T13:00:04Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":20}}}}
            """
        ]

        let fixture = try TopDollarFixture.make(lines: lines)
        defer { fixture.cleanup() }

        let parser = fixture.parser()
        let insights = parser.calculateInsights()

        let turn = try #require(insights.expensiveTurns.first)
        #expect(turn.model == "gpt-5.4-mini")
    }

    @Test
    func insightsAggregateMultipleTokenEventsIntoSingleTurn() throws {
        let lines = [
            """
            {"timestamp":"2026-04-03T14:00:00Z","type":"session_meta","payload":{"id":"session-stream","cwd":"/tmp/demo"}}
            """,
            """
            {"timestamp":"2026-04-03T14:00:01Z","type":"event_msg","payload":{"type":"task_started"}}
            """,
            """
            {"timestamp":"2026-04-03T14:00:02Z","type":"event_msg","payload":{"type":"user_message","message":"streamed turn"}}
            """,
            """
            {"timestamp":"2026-04-03T14:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10}}}}
            """,
            """
            {"timestamp":"2026-04-03T14:00:04Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":180,"output_tokens":40}}}}
            """
        ]

        let fixture = try TopDollarFixture.make(lines: lines)
        defer { fixture.cleanup() }

        let parser = fixture.parser()
        let insights = parser.calculateInsights()

        let turn = try #require(insights.expensiveTurns.first)
        #expect(insights.expensiveTurns.count == 1)
        #expect(turn.promptPreview == "streamed turn")
        #expect(turn.inputTokens == 180)
        #expect(turn.outputTokens == 40)

        let project = try #require(insights.projects.first)
        #expect(project.tokens == 220)
    }

    @Test
    func insightsHeatmapUsesTurnTimestampsInsteadOfSessionStart() throws {
        let lines = [
            """
            {"timestamp":"2026-04-03T01:00:00Z","type":"session_meta","payload":{"id":"session-heatmap","cwd":"/tmp/demo"}}
            """,
            """
            {"timestamp":"2026-04-03T01:00:01Z","type":"event_msg","payload":{"type":"task_started"}}
            """,
            """
            {"timestamp":"2026-04-03T01:00:02Z","type":"event_msg","payload":{"type":"user_message","message":"early turn"}}
            """,
            """
            {"timestamp":"2026-04-03T01:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":20}}}}
            """,
            """
            {"timestamp":"2026-04-03T18:00:01Z","type":"event_msg","payload":{"type":"task_started"}}
            """,
            """
            {"timestamp":"2026-04-03T18:00:02Z","type":"event_msg","payload":{"type":"user_message","message":"late turn"}}
            """,
            """
            {"timestamp":"2026-04-03T18:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":50,"output_tokens":10}}}}
            """
        ]

        let fixture = try TopDollarFixture.make(lines: lines)
        defer { fixture.cleanup() }

        let parser = fixture.parser()
        let insights = parser.calculateInsights()

        let calendar = Calendar.current
        let formatter = ISO8601DateFormatter()

        func bucket(for timestamp: String) throws -> (dayOfWeek: Int, hour: Int) {
            let date = try #require(formatter.date(from: timestamp))
            let weekday = calendar.component(.weekday, from: date)
            let rawDay = weekday - 1
            let dayOfWeek = rawDay == 0 ? 6 : rawDay - 1
            let hour = calendar.component(.hour, from: date)
            return (dayOfWeek, hour)
        }

        let earlyBucket = try bucket(for: "2026-04-03T01:00:03Z")
        let lateBucket = try bucket(for: "2026-04-03T18:00:03Z")

        let early = insights.hourlyActivity.first { $0.dayOfWeek == earlyBucket.dayOfWeek && $0.hour == earlyBucket.hour }
        let late = insights.hourlyActivity.first { $0.dayOfWeek == lateBucket.dayOfWeek && $0.hour == lateBucket.hour }

        #expect(early?.tokens == 120)
        #expect(late?.tokens == 60)
    }
}

private extension SessionFixture {
    static func make() throws -> TopDollarFixture {
        try make(lines: [
            """
            {"timestamp":"2026-04-03T10:00:00Z","type":"session_meta","payload":{"id":"session-1","cwd":"/tmp/demo"}}
            """,
            """
            {"timestamp":"2026-04-03T10:00:01Z","type":"event_msg","payload":{"type":"task_started"}}
            """,
            """
            {"timestamp":"2026-04-03T10:00:02Z","type":"event_msg","payload":{"type":"user_message","message":"cached-heavy turn"}}
            """,
            """
            {"timestamp":"2026-04-03T10:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":900,"output_tokens":10}}}}
            """,
            """
            {"timestamp":"2026-04-03T10:00:04Z","type":"turn_context","payload":{"model":"gpt-5-mini"}}
            """,
            """
            {"timestamp":"2026-04-03T10:00:05Z","type":"event_msg","payload":{"type":"task_started"}}
            """,
            """
            {"timestamp":"2026-04-03T10:00:06Z","type":"event_msg","payload":{"type":"user_message","message":"mini turn"}}
            """,
            """
            {"timestamp":"2026-04-03T10:00:07Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2000,"output_tokens":100}}}}
            """
        ])
    }
}

private typealias TopDollarFixture = SessionFixture
