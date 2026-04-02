import Foundation

struct UpdateChecker: Sendable {

    private static let apiURL = URL(string: "https://api.github.com/repos/senoldogann/codex-switcher/releases/latest")!

    struct Release: Sendable {
        let version: String
        let releaseURL: URL
        let tagName: String
    }

    /// Fetches the latest GitHub release and returns it if newer than the running version.
    static func fetchIfNewer() async -> Release? {
        guard let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return nil }

        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlURL = json["html_url"] as? String,
              let releaseURL = URL(string: htmlURL) else { return nil }

        // Strip leading "v" and handle tags like "v1.9.0-signed"
        let clean = tagName
            .hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        let version = clean.components(separatedBy: "-").first ?? clean

        guard isNewer(version, than: current) else { return nil }
        return Release(version: version, releaseURL: releaseURL, tagName: tagName)
    }

    private static func isNewer(_ remote: String, than current: String) -> Bool {
        let parse: (String) -> [Int] = { s in
            s.split(separator: ".").compactMap { Int($0) }
        }
        let r = parse(remote), c = parse(current)
        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }
}
