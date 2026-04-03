import Foundation

struct SwitchOrchestrator {
    private(set) var state: SwitchOrchestrationState = .idle
    private(set) var pendingRequest: PendingSwitchRequest?
    private(set) var verificationAttempt: SeamlessVerificationAttempt?
    private(set) var lastResult: SeamlessSwitchResult?
    private(set) var reliability = SwitchReliabilitySnapshot()

    mutating func queue(request: PendingSwitchRequest, detail: String, now: Date = Date()) -> Bool {
        guard pendingRequest == nil else { return false }

        pendingRequest = request
        state = .pendingSwitch
        reliability.pendingSwitchCount += 1
        lastResult = SeamlessSwitchResult(
            outcome: .deferred,
            recordedAt: now,
            detail: detail
        )
        return true
    }

    mutating func readySwitchIfPossible(isSessionActive: Bool) -> PendingSwitchRequest? {
        guard let pendingRequest, !isSessionActive else { return nil }

        self.pendingRequest = nil
        state = .readyToSwitch
        reliability.completedDeferredSwitchCount += 1
        return pendingRequest
    }

    mutating func startVerifying(targetProfileId: UUID, targetProfileName: String, now: Date = Date()) {
        verificationAttempt = SeamlessVerificationAttempt(
            targetProfileId: targetProfileId,
            targetProfileName: targetProfileName,
            startedAt: now
        )
        state = .verifying
    }

    mutating func completeSeamlessSuccess(detail: String, now: Date = Date()) {
        verificationAttempt = nil
        state = .idle
        reliability.seamlessSuccessCount += 1
        lastResult = SeamlessSwitchResult(
            outcome: .seamlessSuccess,
            recordedAt: now,
            detail: detail
        )
    }

    mutating func markInconclusive(detail: String, now: Date = Date()) {
        verificationAttempt = nil
        state = .idle
        reliability.inconclusiveCount += 1
        lastResult = SeamlessSwitchResult(
            outcome: .inconclusive,
            recordedAt: now,
            detail: detail
        )
    }

    mutating func finishSwitchCycle() {
        state = .idle
    }

    mutating func clearPending() {
        pendingRequest = nil
        verificationAttempt = nil
        state = .idle
    }

    mutating func recordFallbackRestart(detail: String, now: Date = Date()) {
        verificationAttempt = nil
        pendingRequest = nil
        state = .idle
        reliability.fallbackRestartCount += 1
        lastResult = SeamlessSwitchResult(
            outcome: .fallbackRestart,
            recordedAt: now,
            detail: detail
        )
    }
}
