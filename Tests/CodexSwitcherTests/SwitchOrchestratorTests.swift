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
        let request = PendingSwitchRequest(
            targetProfileId: UUID(),
            targetProfileName: "Account 2",
            reason: "Limit reached",
            queuedAt: Date()
        )
        _ = orchestrator.queue(request: request, detail: "deferred")

        #expect(orchestrator.readySwitchIfPossible(isSessionActive: true) == nil)
        #expect(orchestrator.state == .pendingSwitch)

        let ready = orchestrator.readySwitchIfPossible(isSessionActive: false)

        #expect(ready == request)
        #expect(orchestrator.pendingRequest == nil)
        #expect(orchestrator.state == .readyToSwitch)
        #expect(orchestrator.reliability.completedDeferredSwitchCount == 1)
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
    }

    @Test
    func completeSeamlessSuccessClearsVerification() {
        var orchestrator = SwitchOrchestrator()
        orchestrator.startVerifying(
            targetProfileId: UUID(),
            targetProfileName: "Account 2"
        )

        orchestrator.completeSeamlessSuccess(detail: "Seamless switch verified.")

        #expect(orchestrator.state == .idle)
        #expect(orchestrator.verificationAttempt == nil)
        #expect(orchestrator.lastResult?.outcome == .seamlessSuccess)
        #expect(orchestrator.reliability.seamlessSuccessCount == 1)
    }

    @Test
    func markInconclusiveClearsVerification() {
        var orchestrator = SwitchOrchestrator()
        orchestrator.startVerifying(
            targetProfileId: UUID(),
            targetProfileName: "Account 2"
        )

        orchestrator.markInconclusive(detail: "No request observed.")

        #expect(orchestrator.state == .idle)
        #expect(orchestrator.verificationAttempt == nil)
        #expect(orchestrator.lastResult?.outcome == .inconclusive)
        #expect(orchestrator.reliability.inconclusiveCount == 1)
    }
}
