import Foundation
import AppKit

// MARK: - Session Activity & Pending Switch

extension AppStore {

    func recordSessionActivity() {
        sessionActivitySequence += 1
        let currentSequence = sessionActivitySequence
        isSessionActive = true
        scheduleSeamlessVerificationSuccess(sequence: currentSequence)

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.sessionActivitySequence == currentSequence else { return }
            self.isSessionActive = false
            self.processPendingSwitchIfNeeded(trigger: "session-idle")
        }
    }

    func queuePendingSwitch(reason: String) {
        guard switchOrchestrator.pendingRequest == nil else { return }
        guard let candidate = smartNextProfile(auto: true) else {
            allExhausted = true
            sendNotification(title: Str.allExhausted, body: L("Limitler sıfırlanınca devam eder.", "Will resume when limits reset."))
            return
        }

        let request = PendingSwitchRequest(
            targetProfileId: candidate.id,
            targetProfileName: candidate.displayName,
            reason: reason,
            queuedAt: Date()
        )
        _ = switchOrchestrator.queue(
            request: request,
            detail: L("Aktif iş bitene kadar geçiş ertelendi.", "Switch was deferred until the active work finished.")
        )
        syncSwitchOrchestrationState()
    }

    func processPendingSwitchIfNeeded(trigger: String) {
        guard let pending = switchOrchestrator.readySwitchIfPossible(
            isSessionActive: isSessionActive,
            now: Date()
        ) else { return }
        guard let candidate = profiles.first(where: { $0.id == pending.targetProfileId }) else {
            switchOrchestrator.clearPending()
            syncSwitchOrchestrationState()
            return
        }

        syncSwitchOrchestrationState()
        switchTo(profile: candidate, reason: "\(pending.reason) · \(trigger)")
        switchOrchestrator.finishSwitchCycle()
        syncSwitchOrchestrationState()
    }

    // MARK: - Seamless Verification

    func attemptSeamlessSwitch(for candidate: Profile) {
        guard isCodexRunning() else {
            switchOrchestrator.markInconclusive(
                detail: L(
                    "Codex çalışmıyordu; geçiş yeniden başlatma gerektirmeden tamamlandı.",
                    "Codex was not running, so the switch completed without needing a restart."
                )
            )
            syncSwitchOrchestrationState()
            return
        }

        seamlessVerificationWork?.cancel()
        switchOrchestrator.recordImmediateRestart(
            targetProfileName: candidate.displayName,
            detail: L(
                "Yeni hesabın aktif kalmasını garanti etmek için Codex yeniden başlatıldı.",
                "Codex was restarted to guarantee the new account became active."
            )
        )
        syncSwitchOrchestrationState()
        restartAIIfRunning(for: candidate)
    }

    private func scheduleSeamlessVerificationSuccess(sequence: Int) {
        guard switchOrchestrationState == .verifying else { return }

        seamlessVerificationWork?.cancel()
        let successWork = DispatchWorkItem { [weak self] in
            guard let self,
                  self.switchOrchestrationState == .verifying,
                  self.sessionActivitySequence == sequence,
                  let activeProfile else { return }

            let verifyResult = self.profileManager.verifyActiveAccount(expectedAccountId: activeProfile.accountId)
            guard case .verified = verifyResult else { return }

            self.switchOrchestrator.completeSeamlessSuccess(
                detail: L(
                    "Yeni oturum aktivitesi gözlendi; geçiş yeniden başlatmasız doğrulandı.",
                    "New session activity was observed; the switch was verified without restarting."
                )
            )
            self.syncSwitchOrchestrationState()
        }
        seamlessVerificationWork = successWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: successWork)
    }

    func handleSeamlessVerificationFailure() {
        guard let activeProfile else { return }
        seamlessVerificationWork?.cancel()
        switchOrchestrator.recordFallbackRestart(
            detail: L(
                "Yeni istek sonrası limit hatası devam etti; yeniden başlatma fallback uygulandı.",
                "Rate-limit behavior persisted after the switch; restart fallback was applied."
            )
        )
        syncSwitchOrchestrationState()
        restartAIIfRunning(for: activeProfile)
    }

    func isCodexRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.localizedName == "Codex" && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }
    }

    func syncSwitchOrchestrationState() {
        switchOrchestrationState  = switchOrchestrator.state
        pendingSwitchRequest      = switchOrchestrator.pendingRequest
        lastSeamlessSwitchResult  = switchOrchestrator.lastResult
        switchReliability         = switchOrchestrator.reliability

        let timelineEvents = switchOrchestrator.timelineEvents
        if timelineEvents.count > syncedTimelineEventCount {
            let newEvents = Array(timelineEvents.dropFirst(syncedTimelineEventCount))
            for event in newEvents { switchTimelineStore.append(event) }
            switchTimeline.append(contentsOf: newEvents)
            syncedTimelineEventCount = timelineEvents.count
        }
        refreshReliabilityAnalytics()
    }

    // MARK: - Reliability Analytics

    func refreshReliabilityAnalytics(now: Date = Date()) {
        automationConfidence = AutomationConfidenceCalculator.buildSummary(
            profiles: profiles,
            staleProfileIds: staleProfileIds,
            rateLimitHealth: rateLimitHealth,
            reliability: switchReliability,
            pendingSwitchRequest: pendingSwitchRequest,
            switchTimeline: switchTimeline,
            now: now
        )
        accountReliability = AutomationConfidenceCalculator.buildAccountSummaries(
            profiles: profiles,
            staleProfileIds: staleProfileIds,
            rateLimitHealth: rateLimitHealth,
            forecasts: forecasts,
            costs: costs,
            now: now
        )
        emitAutomationAlertIfNeeded()
    }

    func startAutomationHealthPolling() {
        automationHealthTimer?.invalidate()
        automationHealthTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshReliabilityAnalytics() }
        }
    }

    private func emitAutomationAlertIfNeeded() {
        guard let alert = AutomationAlertPolicy.nextAlert(
            summary: automationConfidence,
            previousFingerprint: lastAutomationAlertFingerprint
        ) else { return }
        lastAutomationAlertFingerprint = alert.fingerprint
        sendNotification(title: alert.title, body: alert.body)
    }
}
