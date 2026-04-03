import Foundation

struct UpdateChecker: Sendable {

    private static let apiURL = URL(string: "https://api.github.com/repos/senoldogann/codex-switcher/releases/latest")!

    private struct GitHubReleaseDTO: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    static func currentVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    static func check() async -> UpdateStatusSnapshot {
        let current = currentVersion()
        let checkedAt = Date()

        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let snapshot = try snapshot(from: data, currentVersion: current, checkedAt: checkedAt) else {
                return UpdateStatusSnapshot(
                    currentVersion: current,
                    latestVersion: nil,
                    release: nil,
                    lastCheckedAt: checkedAt,
                    state: .failed,
                    errorSummary: "Invalid release payload"
                )
            }
            return snapshot
        } catch {
            return UpdateStatusSnapshot(
                currentVersion: current,
                latestVersion: nil,
                release: nil,
                lastCheckedAt: checkedAt,
                state: .failed,
                errorSummary: error.localizedDescription
            )
        }
    }

    static func snapshot(from data: Data, currentVersion: String, checkedAt: Date) throws -> UpdateStatusSnapshot? {
        let release = try decodeRelease(from: data)
        return snapshot(from: release, currentVersion: currentVersion, checkedAt: checkedAt)
    }

    static func decodeRelease(from data: Data) throws -> UpdateReleaseInfo {
        let dto = try JSONDecoder().decode(GitHubReleaseDTO.self, from: data)
        let clean = dto.tagName.hasPrefix("v") ? String(dto.tagName.dropFirst()) : dto.tagName
        let version = clean.components(separatedBy: "-").first ?? clean
        guard let releaseURL = URL(string: dto.htmlURL) else {
            throw URLError(.badServerResponse)
        }
        return UpdateReleaseInfo(version: version, releaseURL: releaseURL, tagName: dto.tagName)
    }

    static func snapshot(from release: UpdateReleaseInfo, currentVersion: String, checkedAt: Date) -> UpdateStatusSnapshot {
        let state: UpdateCheckState = isNewer(release.version, than: currentVersion) ? .updateAvailable : .upToDate
        return UpdateStatusSnapshot(
            currentVersion: currentVersion,
            latestVersion: release.version,
            release: release,
            lastCheckedAt: checkedAt,
            state: state,
            errorSummary: nil
        )
    }

    static func isNewer(_ remote: String, than current: String) -> Bool {
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
