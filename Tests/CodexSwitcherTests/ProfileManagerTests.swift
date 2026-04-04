import Foundation
import Testing
@testable import CodexSwitcher

struct ProfileManagerTests {

    // MARK: - Helpers

    /// Creates a signed-less JWT (header.payload.fake) with the given payload.
    private func makeJWT(payload: [String: Any]) -> String {
        let header = Data("{\"alg\":\"none\"}".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        let payloadB64 = payloadData
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        return "\(header).\(payloadB64).fake"
    }

    // MARK: - extractAccountId

    @Test("extractAccountId returns chatgpt_account_id from well-formed JWT")
    func extractAccountIdFromValidJWT() {
        let pm = ProfileManager()
        let jwt = makeJWT(payload: [
            "https://api.openai.com/auth": ["chatgpt_account_id": "user-abc123"]
        ])
        #expect(pm.extractAccountId(from: jwt) == "user-abc123")
    }

    @Test("extractAccountId returns nil when top-level auth key is absent")
    func extractAccountIdMissingTopLevelKey() {
        let pm = ProfileManager()
        let jwt = makeJWT(payload: ["sub": "irrelevant"])
        #expect(pm.extractAccountId(from: jwt) == nil)
    }

    @Test("extractAccountId returns nil when nested chatgpt_account_id key is absent")
    func extractAccountIdMissingNestedKey() {
        let pm = ProfileManager()
        let jwt = makeJWT(payload: [
            "https://api.openai.com/auth": ["other_field": "value"]
        ])
        #expect(pm.extractAccountId(from: jwt) == nil)
    }

    @Test("extractAccountId returns nil for a non-JWT string")
    func extractAccountIdForNonJWT() {
        let pm = ProfileManager()
        #expect(pm.extractAccountId(from: "not-a-jwt") == nil)
        #expect(pm.extractAccountId(from: "") == nil)
    }

    @Test("extractAccountId returns nil when payload segment is not valid base64-JSON")
    func extractAccountIdInvalidPayloadSegment() {
        let pm = ProfileManager()
        #expect(pm.extractAccountId(from: "header.!!!invalid!!!.sig") == nil)
    }

    @Test("extractAccountId handles base64 segments that need padding")
    func extractAccountIdPaddingRestored() {
        // makeJWT strips '=' padding; the parser must restore it before decoding.
        let pm = ProfileManager()
        let jwt = makeJWT(payload: [
            "https://api.openai.com/auth": ["chatgpt_account_id": "acct-xyz789"]
        ])
        // Verify the payload segment has no '=' before parsing — confirms the test
        // actually exercises the padding-restoration path in extractClaim.
        let segment = jwt.components(separatedBy: ".")[1]
        #expect(!segment.contains("="))
        #expect(pm.extractAccountId(from: jwt) == "acct-xyz789")
    }

    // MARK: - extractEmail

    @Test("extractEmail returns email from well-formed JWT")
    func extractEmailFromValidJWT() {
        let pm = ProfileManager()
        let jwt = makeJWT(payload: [
            "https://api.openai.com/profile": ["email": "dev@example.com"]
        ])
        #expect(pm.extractEmail(from: jwt) == "dev@example.com")
    }

    @Test("extractEmail returns nil when profile key is absent")
    func extractEmailMissingProfileKey() {
        let pm = ProfileManager()
        let jwt = makeJWT(payload: ["sub": "user-999"])
        #expect(pm.extractEmail(from: jwt) == nil)
    }

    @Test("extractEmail returns nil when email field is absent inside profile")
    func extractEmailMissingEmailField() {
        let pm = ProfileManager()
        let jwt = makeJWT(payload: [
            "https://api.openai.com/profile": ["name": "Alice"]
        ])
        #expect(pm.extractEmail(from: jwt) == nil)
    }

    // MARK: - Both claims in one JWT

    @Test("extractAccountId and extractEmail both resolve from a single JWT")
    func bothClaimsFromOneJWT() {
        let pm = ProfileManager()
        let jwt = makeJWT(payload: [
            "https://api.openai.com/auth":    ["chatgpt_account_id": "acct-multi"],
            "https://api.openai.com/profile": ["email": "multi@example.com"]
        ])
        #expect(pm.extractAccountId(from: jwt) == "acct-multi")
        #expect(pm.extractEmail(from: jwt) == "multi@example.com")
    }
}
