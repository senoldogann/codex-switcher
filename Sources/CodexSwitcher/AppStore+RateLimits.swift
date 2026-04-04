import Foundation
import AppKit

// MARK: - Rate Limit Polling & Fetch

extension AppStore {

    func startRateLimitPolling() {
        Task { await fetchAllRateLimits(showSpinner: false) }
        rateLimitTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.fetchAllRateLimits(showSpinner: false) }
        }
    }

    func fetchAllRateLimits(showSpinner: Bool = true) async {
        if showSpinner { isFetchingLimits = true }
        defer { if showSpinner { isFetchingLimits = false } }

        let fetcher = self.fetcher
        let activeProfileId = activeProfile?.id
        let credPairs: [(UUID, AuthCredentials)] = profiles.compactMap { profile in
            let dict: [String: Any]?
            if profile.id == activeProfileId,
               let liveDict = profileManager.readLiveAuthDict() {
                dict = liveDict
            } else {
                dict = profileManager.readAuthDict(for: profile)
            }
            guard let dict,
                  let creds = fetcher.credentials(from: dict) else { return nil }
            return (profile.id, creds)
        }

        var results: [(UUID, FetchResult)] = []
        await withTaskGroup(of: (UUID, FetchResult).self) { group in
            for (id, creds) in credPairs {
                group.addTask {
                    let result = await fetcher.fetch(credentials: creds)
                    return (id, result)
                }
            }
            for await pair in group { results.append(pair) }
        }

        var newStale: Set<UUID> = []
        var successCount = 0
        for (id, result) in results {
            switch result {
            case .success(let info, let diagnostic):
                rateLimits[id] = info
                appendRateLimitAuditSample(for: id, info: info, checkedAt: diagnostic.checkedAt)
                successCount += 1
                let previous = rateLimitHealth[id] ?? RateLimitHealthStatus()
                rateLimitHealth[id] = RateLimitHealthStatus(
                    lastCheckedAt: diagnostic.checkedAt,
                    lastSuccessfulFetchAt: diagnostic.checkedAt,
                    lastFailedFetchAt: previous.lastFailedFetchAt,
                    lastHTTPStatusCode: diagnostic.httpStatusCode,
                    staleReason: nil,
                    failureSummary: nil
                )
                let profileName = profiles.first(where: { $0.id == id })?.displayName ?? L("Hesap", "Account")
                if lastKnownLimitState[id] == true, info.limitReached == false {
                    sendNotification(
                        title: L("Limit sıfırlandı", "Limit reset"),
                        body: L("\(profileName) kullanıma hazır", "\(profileName) is ready to use again")
                    )
                    warned80PercentIds.remove(id)
                }
                lastKnownLimitState[id] = info.limitReached
                if let used = info.weeklyUsedPercent,
                   used >= 80, !info.limitReached,
                   !warned80PercentIds.contains(id) {
                    warned80PercentIds.insert(id)
                    sendNotification(
                        title: L("Limit uyarısı", "Limit warning"),
                        body: L("\(profileName) haftalık limitinin %\(100 - used)'i kaldı", "\(profileName) has \(100 - used)% weekly limit remaining")
                    )
                }
            case .stale(let diagnostic):
                newStale.insert(id)
                let previous = rateLimitHealth[id] ?? RateLimitHealthStatus()
                rateLimitHealth[id] = RateLimitHealthStatus(
                    lastCheckedAt: diagnostic.checkedAt,
                    lastSuccessfulFetchAt: previous.lastSuccessfulFetchAt,
                    lastFailedFetchAt: diagnostic.checkedAt,
                    lastHTTPStatusCode: diagnostic.httpStatusCode,
                    staleReason: diagnostic.staleReason,
                    failureSummary: diagnostic.failureSummary
                )
            case .failure(let diagnostic):
                let previous = rateLimitHealth[id] ?? RateLimitHealthStatus()
                rateLimitHealth[id] = RateLimitHealthStatus(
                    lastCheckedAt: diagnostic.checkedAt,
                    lastSuccessfulFetchAt: previous.lastSuccessfulFetchAt,
                    lastFailedFetchAt: diagnostic.checkedAt,
                    lastHTTPStatusCode: diagnostic.httpStatusCode,
                    staleReason: nil,
                    failureSummary: diagnostic.failureSummary
                )
            }
        }

        if successCount == 0, !credPairs.isEmpty {
            consecutiveFetchFailures += 1
            if consecutiveFetchFailures >= 3 { return }
        } else {
            consecutiveFetchFailures = 0
        }

        staleProfileIds = newStale
        refreshReliabilityAnalytics()
        NotificationCenter.default.post(name: .rateLimitsUpdated, object: nil)
        evaluateAutomaticSwitchAfterRateLimitRefresh()
        refreshTokenUsage()
    }

    func appendRateLimitAuditSample(for profileId: UUID, info: RateLimitInfo, checkedAt: Date) {
        let sample = RateLimitAuditSample(
            timestamp: checkedAt,
            weeklyRemainingPercent: info.weeklyRemainingPercent,
            fiveHourRemainingPercent: info.fiveHourRemainingPercent,
            limitReached: info.limitReached
        )
        var samples = rateLimitAuditSamples[profileId] ?? []
        if let last = samples.last,
           last.weeklyRemainingPercent == sample.weeklyRemainingPercent,
           last.fiveHourRemainingPercent == sample.fiveHourRemainingPercent,
           last.limitReached == sample.limitReached,
           checkedAt.timeIntervalSince(last.timestamp) < 60 {
            return
        }
        samples.append(sample)
        if samples.count > 240 { samples.removeFirst(samples.count - 240) }
        rateLimitAuditSamples[profileId] = samples
    }
}
