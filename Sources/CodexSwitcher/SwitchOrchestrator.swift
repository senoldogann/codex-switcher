import Foundation

struct SwitchOrchestrator {
    private(set) var state: SwitchOrchestrationState = .idle
    private(set) var pendingRequest: PendingSwitchRequest?
    private(set) var verificationAttempt: SeamlessVerificationAttempt?
    private(set) var lastResult: SeamlessSwitchResult?
    private(set) var reliability = SwitchReliabilitySnapshot()
    private(set) var timelineEvents: [SwitchTimelineEvent] = []

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
        appendTimelineEvent(
            stage: .queued,
            timestamp: now,
            targetProfileName: request.targetProfileName,
            reason: request.reason,
            detail: detail
        )
        return true
    }

    mutating func readySwitchIfPossible(isSessionActive: Bool, now: Date = Date()) -> PendingSwitchRequest? {
        guard let pendingRequest, !isSessionActive else { return nil }

        self.pendingRequest = nil
        state = .readyToSwitch
        reliability.completedDeferredSwitchCount += 1
        appendTimelineEvent(
            stage: .ready,
            timestamp: now,
            targetProfileName: pendingRequest.targetProfileName,
            reason: pendingRequest.reason,
            detail: "Pending switch is ready to execute.",
            waitDurationSeconds: max(0, Int(now.timeIntervalSince(pendingRequest.queuedAt).rounded()))
        )
        return pendingRequest
    }

    mutating func startVerifying(targetProfileId: UUID, targetProfileName: String, now: Date = Date()) {
        verificationAttempt = SeamlessVerificationAttempt(
            targetProfileId: targetProfileId,
            targetProfileName: targetProfileName,
            startedAt: now
        )
        state = .verifying
        appendTimelineEvent(
            stage: .verifying,
            timestamp: now,
            targetProfileName: targetProfileName,
            detail: "Seamless switch verification started."
        )
    }

    mutating func completeSeamlessSuccess(detail: String, now: Date = Date()) {
        let verificationDurationSeconds = verificationAttempt.map {
            max(0, Int(now.timeIntervalSince($0.startedAt).rounded()))
        }
        let targetProfileName = verificationAttempt?.targetProfileName ?? "Unknown"
        verificationAttempt = nil
        state = .idle
        reliability.seamlessSuccessCount += 1
        lastResult = SeamlessSwitchResult(
            outcome: .seamlessSuccess,
            recordedAt: now,
            detail: detail
        )
        appendTimelineEvent(
            stage: .seamlessSuccess,
            timestamp: now,
            targetProfileName: targetProfileName,
            detail: detail,
            verificationDurationSeconds: verificationDurationSeconds
        )
    }

    mutating func markInconclusive(detail: String, now: Date = Date()) {
        let verificationDurationSeconds = verificationAttempt.map {
            max(0, Int(now.timeIntervalSince($0.startedAt).rounded()))
        }
        let targetProfileName = verificationAttempt?.targetProfileName ?? "Unknown"
        verificationAttempt = nil
        state = .idle
        reliability.inconclusiveCount += 1
        lastResult = SeamlessSwitchResult(
            outcome: .inconclusive,
            recordedAt: now,
            detail: detail
        )
        appendTimelineEvent(
            stage: .inconclusive,
            timestamp: now,
            targetProfileName: targetProfileName,
            detail: detail,
            verificationDurationSeconds: verificationDurationSeconds
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
        let verificationDurationSeconds = verificationAttempt.map {
            max(0, Int(now.timeIntervalSince($0.startedAt).rounded()))
        }
        let targetProfileName = verificationAttempt?.targetProfileName ?? pendingRequest?.targetProfileName ?? "Unknown"
        finalizeFallbackRestart(
            targetProfileName: targetProfileName,
            detail: detail,
            verificationDurationSeconds: verificationDurationSeconds,
            now: now
        )
    }

    mutating func recordImmediateRestart(
        targetProfileName: String,
        detail: String,
        now: Date = Date()
    ) {
        finalizeFallbackRestart(
            targetProfileName: targetProfileName,
            detail: detail,
            verificationDurationSeconds: nil,
            now: now
        )
    }

    mutating func recordBlockedDecision(
        targetProfileName: String,
        reason: String,
        detail: String,
        now: Date = Date()
    ) {
        state = .idle
        reliability.blockedDecisionCount += 1
        appendTimelineEvent(
            stage: .blocked,
            timestamp: now,
            targetProfileName: targetProfileName,
            reason: reason,
            detail: detail
        )
    }

    mutating func recordHaltedDecision(reason: String, detail: String, now: Date = Date()) {
        state = .idle
        reliability.haltedDecisionCount += 1
        appendTimelineEvent(
            stage: .halted,
            timestamp: now,
            targetProfileName: "Automation",
            reason: reason,
            detail: detail
        )
    }

    private mutating func finalizeFallbackRestart(
        targetProfileName: String,
        detail: String,
        verificationDurationSeconds: Int?,
        now: Date
    ) {
        verificationAttempt = nil
        pendingRequest = nil
        state = .idle
        reliability.fallbackRestartCount += 1
        lastResult = SeamlessSwitchResult(
            outcome: .fallbackRestart,
            recordedAt: now,
            detail: detail
        )
        appendTimelineEvent(
            stage: .fallbackRestart,
            timestamp: now,
            targetProfileName: targetProfileName,
            detail: detail,
            verificationDurationSeconds: verificationDurationSeconds
        )
    }

    private mutating func appendTimelineEvent(
        stage: SwitchTimelineEvent.Stage,
        timestamp: Date,
        targetProfileName: String,
        reason: String? = nil,
        detail: String,
        waitDurationSeconds: Int? = nil,
        verificationDurationSeconds: Int? = nil
    ) {
        timelineEvents.append(
            SwitchTimelineEvent(
                id: UUID(),
                timestamp: timestamp,
                stage: stage,
                targetProfileName: targetProfileName,
                reason: reason,
                detail: detail,
                waitDurationSeconds: waitDurationSeconds,
                verificationDurationSeconds: verificationDurationSeconds
            )
        )
    }
}
