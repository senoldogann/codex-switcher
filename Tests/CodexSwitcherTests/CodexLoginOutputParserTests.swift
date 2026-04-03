import Foundation
import Testing
@testable import CodexSwitcher

struct CodexLoginOutputParserTests {
    @Test
    func extractsAuthorizationURLFromCLIOutput() throws {
        let output = """
        Starting local login server on http://localhost:1455.
        If your browser did not open, navigate to this URL to authenticate:

        https://auth.openai.com/oauth/authorize?response_type=code&client_id=demo&redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback&scope=openid

        On a remote or headless machine? Use `codex login --device-auth` instead.
        """

        let url = try #require(CodexLoginOutputParser.authorizationURL(in: output))

        #expect(url.host() == "auth.openai.com")
        #expect(url.absoluteString.contains("/oauth/authorize"))
        #expect(url.absoluteString.contains("client_id=demo"))
    }

    @Test
    func ignoresNonAuthorizationURLs() {
        let output = """
        Starting local login server on http://localhost:1455.
        Open docs at https://platform.openai.com/docs
        """

        #expect(CodexLoginOutputParser.authorizationURL(in: output) == nil)
    }
}
