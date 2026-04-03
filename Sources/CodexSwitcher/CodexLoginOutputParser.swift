import Foundation

enum CodexLoginOutputParser {
    static func authorizationURL(in output: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(location: 0, length: output.utf16.count)
        let matches = detector.matches(in: output, options: [], range: range)
        return matches.compactMap(\.url).first { url in
            url.host() == "auth.openai.com" && url.path == "/oauth/authorize"
        }
    }
}
