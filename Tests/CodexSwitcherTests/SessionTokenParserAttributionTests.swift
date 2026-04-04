import Foundation
import Testing
@testable import CodexSwitcher

struct SessionTokenParserAttributionTests {
    @Test
    func calculateAttributesUsageToActiveProfileWhenSwitchHistoryIsEmpty() throws {
        let now = Date()
        let profile = Profile(alias: "Solo", email: "solo@example.com", accountId: "acct-solo", addedAt: now)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: now.addingTimeInterval(-60))

        let fixture = try SessionFixture.make(lines: [
            """
            {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":120,"output_tokens":30}}}}
            """
        ])
        defer { fixture.cleanup() }

        let parser = fixture.parser()

        let usage = parser.calculate(profiles: [profile], history: [], activeProfileId: profile.id)
        let daily = parser.calculateDaily(profiles: [profile], history: [], activeProfileId: profile.id, range: .sevenDays)
        let records = parser.calculateAnalyticsRecords(profiles: [profile], history: [], activeProfileId: profile.id)

        #expect(usage[profile.id]?.totalTokens == 150)
        #expect(daily[profile.id]?.contains(where: { $0.tokens == 150 }) == true)
        #expect(records.count == 1)
        #expect(records.first?.profileId == profile.id)
        #expect(records.first?.totalTokens == 150)
    }
}
