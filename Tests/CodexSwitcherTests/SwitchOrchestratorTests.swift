import Foundation
import Testing
@testable import CodexSwitcher

struct SwitchOrchestratorTests {
    @Test
    func queueCreatesPendingSwitchAndDeferredResult() {
        var orchestrator = SwitchOrchestrator()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let request = PendingSwitchRequest(
            targetProfileId: UUID(),
            targetProfileName: "Account 2",
            reason: "Limit reached",
            queuedAt: now
        )

        let didQueue = orchestrator.queue(
            request: request,
            detail: "Switch was deferred until the active work finished.",
            now: now
        )

        #expect(didQueue == true)
        #expect(orchestrator.state == .pendingSwitch)
        #expect(orchestrator.pendingRequest == request)
        #expect(orchestrator.reliability.pendingSwitchCount == 1)
        #expect(orchestrator.lastResult?.outcome == .deferred)
        #expect(orchestrator.timelineEvents.count == 1)
        #expect(orchestrator.timelineEvents.first?.stage == .queued)
    }

    @Test
    func queueIgnoresDuplicatePendingSwitch() {
        var orchestrator = SwitchOrchestrator()
        let first = PendingSwitchRequest(
            targetProfileId: UUID(),
            targetProfileName: "Account 2",
            reason: "Limit reached",
            queuedAt: Date()
        )
        let second = PendingSwitchRequest(
            targetProfileId: UUID(),
            targetProfileName: "Account 3",
            reason: "Limit reached",
            queuedAt: Date().addingTimeInterval(10)
        )

        #expect(orchestrator.queue(request: first, detail: "deferred") == true)
        #expect(orchestrator.queue(request: second, detail: "deferred") == false)
        #expect(orchestrator.pendingRequest == first)
        #expect(orchestrator.reliability.pendingSwitchCount == 1)
    }

    @Test
    func readySwitchIfPossibleWaitsUntilSessionIsIdle() {
        var orchestrator = SwitchOrchestrator()
        let queuedAt = Date(timeIntervalSince1970: 1_700_000_200)
        let request = PendingSwitchRequest(
            targetProfileId: UUID(),
            targetProfileName: "Account 2",
            reason: "Limit reached",
            queuedAt: queuedAt
        )
        _ = orchestrator.queue(request: request, detail: "deferred", now: queuedAt)

        #expect(orchestrator.readySwitchIfPossible(isSessionActive: true) == nil)
        #expect(orchestrator.state == .pendingSwitch)

        let ready = orchestrator.readySwitchIfPossible(
            isSessionActive: false,
            now: queuedAt.addingTimeInterval(8)
        )

        #expect(ready == request)
        #expect(orchestrator.pendingRequest == nil)
        #expect(orchestrator.state == .readyToSwitch)
        #expect(orchestrator.reliability.completedDeferredSwitchCount == 1)
        #expect(orchestrator.timelineEvents.count == 2)
        #expect(orchestrator.timelineEvents.last?.stage == .ready)
        #expect(orchestrator.timelineEvents.last?.waitDurationSeconds == 8)
    }

    @Test
    func recordFallbackRestartTracksOutcome() {
        var orchestrator = SwitchOrchestrator()

        orchestrator.recordFallbackRestart(detail: "Restart fallback was required.")

        #expect(orchestrator.reliability.fallbackRestartCount == 1)
        #expect(orchestrator.lastResult?.outcome == .fallbackRestart)
    }

    @Test
    func startVerifyingTracksAttempt() {
        var orchestrator = SwitchOrchestrator()
        let profileId = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_500)

        orchestrator.startVerifying(
            targetProfileId: profileId,
            targetProfileName: "Account 2",
            now: now
        )

        #expect(orchestrator.state == .verifying)
        #expect(orchestrator.verificationAttempt?.targetProfileId == profileId)
        #expect(orchestrator.verificationAttempt?.startedAt == now)
        #expect(orchestrator.timelineEvents.last?.stage == .verifying)
    }

    @Test
    func completeSeamlessSuccessClearsVerification() {
        var orchestrator = SwitchOrchestrator()
        let now = Date(timeIntervalSince1970: 1_700_000_600)
        orchestrator.startVerifying(
            targetProfileId: UUID(),
            targetProfileName: "Account 2",
            now: now
        )

        orchestrator.completeSeamlessSuccess(
            detail: "Seamless switch verified.",
            now: now.addingTimeInterval(3)
        )

        #expect(orchestrator.state == .idle)
        #expect(orchestrator.verificationAttempt == nil)
        #expect(orchestrator.lastResult?.outcome == .seamlessSuccess)
        #expect(orchestrator.reliability.seamlessSuccessCount == 1)
        #expect(orchestrator.timelineEvents.last?.stage == .seamlessSuccess)
        #expect(orchestrator.timelineEvents.last?.verificationDurationSeconds == 3)
    }

    @Test
    func markInconclusiveClearsVerification() {
        var orchestrator = SwitchOrchestrator()
        let now = Date(timeIntervalSince1970: 1_700_000_700)
        orchestrator.startVerifying(
            targetProfileId: UUID(),
            targetProfileName: "Account 2",
            now: now
        )

        orchestrator.markInconclusive(
            detail: "No request observed.",
            now: now.addingTimeInterval(45)
        )

        #expect(orchestrator.state == .idle)
        #expect(orchestrator.verificationAttempt == nil)
        #expect(orchestrator.lastResult?.outcome == .inconclusive)
        #expect(orchestrator.reliability.inconclusiveCount == 1)
        #expect(orchestrator.timelineEvents.last?.stage == .inconclusive)
        #expect(orchestrator.timelineEvents.last?.verificationDurationSeconds == 45)
    }

    @Test
    func recordFallbackRestartCapturesTimelineMetadata() {
        var orchestrator = SwitchOrchestrator()
        let now = Date(timeIntervalSince1970: 1_700_000_800)
        orchestrator.startVerifying(
            targetProfileId: UUID(),
            targetProfileName: "Account 4",
            now: now
        )

        orchestrator.recordFallbackRestart(
            detail: "Restart fallback was required.",
            now: now.addingTimeInterval(4)
        )

        #expect(orchestrator.timelineEvents.last?.stage == .fallbackRestart)
        #expect(orchestrator.timelineEvents.last?.verificationDurationSeconds == 4)
    }

    @Test
    func recordImmediateRestartTracksTargetProfileName() {
        var orchestrator = SwitchOrchestrator()

        orchestrator.recordImmediateRestart(
            targetProfileName: "Account 7",
            detail: "Restart was required to guarantee the switch."
        )

        #expect(orchestrator.reliability.fallbackRestartCount == 1)
        #expect(orchestrator.lastResult?.outcome == .fallbackRestart)
        #expect(orchestrator.timelineEvents.last?.targetProfileName == "Account 7")
        #expect(orchestrator.timelineEvents.last?.verificationDurationSeconds == nil)
    }

    @Test
    func recordBlockedDecisionTracksReliabilityAndTimeline() {
        var orchestrator = SwitchOrchestrator()

        orchestrator.recordBlockedDecision(
            targetProfileName: "Account 9",
            reason: "Manual override",
            detail: "Target was unsafe."
        )

        #expect(orchestrator.reliability.blockedDecisionCount == 1)
        #expect(orchestrator.timelineEvents.last?.stage == .blocked)
        #expect(orchestrator.timelineEvents.last?.targetProfileName == "Account 9")
    }

    @Test
    func recordHaltedDecisionTracksReliabilityAndTimeline() {
        var orchestrator = SwitchOrchestrator()

        orchestrator.recordHaltedDecision(
            reason: "Limit reached",
            detail: "No safe target was available."
        )

        #expect(orchestrator.reliability.haltedDecisionCount == 1)
        #expect(orchestrator.timelineEvents.last?.stage == .halted)
        #expect(orchestrator.timelineEvents.last?.targetProfileName == "Automation")
    }
}
