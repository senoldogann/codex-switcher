import Foundation
import UserNotifications
import AppKit
import SwiftUI

@MainActor
final class AppStore: ObservableObject {

    static let shared = AppStore()

    @Published var profiles: [Profile] = []
    @Published var activeProfile: Profile?
    @Published var isAddingAccount: Bool = false
    @Published var addingStep: AddingStep = .idle
    @Published var addAccountErrorMessage: String?
    @Published var pendingProfileEmail: String = ""
    @Published var aliasText: String = ""
    @Published var allExhausted: Bool = false
    @Published var activeTurns: Int = 0
    @Published var rateLimits: [UUID: RateLimitInfo] = [:]
    @Published var isFetchingLimits: Bool = false
    @Published var switchHistory: [SwitchEvent] = []
    @Published var tokenUsage: [UUID: AccountTokenUsage] = [:]
    @Published var staleProfileIds: Set<UUID> = []
    @Published var rateLimitHealth: [UUID: RateLimitHealthStatus] = [:]
    @Published var costs: [UUID: Double] = [:]
    @Published var forecasts: [UUID: RateLimitForecast] = [:]
    @Published var lastKnownLimitState: [UUID: Bool] = [:]
    @Published var isSessionActive: Bool = false

    @Published var updateStatus: UpdateStatusSnapshot = .idle(currentVersion: UpdateChecker.currentVersion())
    @Published var analyticsTimeRange: AnalyticsTimeRange = .sevenDays
    @Published var analyticsSnapshot: AnalyticsSnapshot = .empty(for: .sevenDays)
    @Published var switchOrchestrationState: SwitchOrchestrationState = .idle
    @Published var pendingSwitchRequest: PendingSwitchRequest?
    @Published var lastSeamlessSwitchResult: SeamlessSwitchResult?
    @Published var switchReliability = SwitchReliabilitySnapshot()
    @Published var switchTimeline: [SwitchTimelineEvent] = []
    @Published var switchDecisionHistory: [SwitchDecisionRecord] = []
    @Published var automationConfidence: AutomationConfidenceSummary = .empty
    @Published var accountReliability: [AccountReliabilitySummary] = []

    // Stored properties — internal so extension files can access them
    var lastBudgetAlertDate: Date?
    var lastWeeklySummaryDate: Date?

    var availableUpdate: UpdateReleaseInfo? {
        updateStatus.state == .updateAvailable ? updateStatus.release : nil
    }

    var powerUserRecommendation: PowerUserRecommendation? {
        PowerUserRecommendationEngine.build(
            automation: automationConfidence,
            diagnostics: analyticsSnapshot.diagnosticsSummary,
            workflow: analyticsSnapshot.workflowSummary
        )
    }

    static let turnsLimit    = 50
    static let switchCooldown: TimeInterval = 60

    let profileManager    = ProfileManager()
    let usageMonitor      = UsageMonitor()
    let usageTracker      = SessionUsageTracker()
    let fetcher           = RateLimitFetcher()
    let historyStore      = SwitchHistoryStore()
    let switchTimelineStore = SwitchTimelineStore()
    let switchDecisionStore = SwitchDecisionStore()
    let codexStateStore = CodexStateStore()
    let tokenParser       = SessionTokenParser()
    let analyticsEngine   = AnalyticsEngine()
    let switchDecisionPolicy = SwitchDecisionPolicy()

    var usageTimer: Timer?
    var rateLimitTimer: Timer?
    var automationHealthTimer: Timer?
    var authWatcher: DispatchSourceFileSystemObject?
    var authWatcherFd: Int32 = -1
    var loginTimeout: DispatchWorkItem?
    var loginProcess: Process?
    var loginOutputPipe: Pipe?
    var loginOutputBuffer = ""
    var didOpenLoginBrowser = false
    var suppressLoginFailureFeedback = false
    var lastAutoSwitchDate: Date?
    var rateLimitCheckPending = false
    var lastAuthWriteDate: Date?
    var consecutiveFetchFailures: Int = 0
    var paceHistory: [SessionPacePoint] = []
    var tokenRefreshWork: DispatchWorkItem?
    var isTokenRefreshRunning = false
    var shouldRefreshTokenUsageAfterCurrentRun = false
    var warned80PercentIds: Set<UUID> = []
    var reloginTargetId: UUID?
    var sessionActivitySequence = 0
    var switchOrchestrator = SwitchOrchestrator()
    var seamlessVerificationWork: DispatchWorkItem?
    var syncedTimelineEventCount = 0
    var lastAutomationAlertFingerprint: String?
    var analyticsWindow: NSWindow?
    var addAccountWindow: NSWindow?
    var rateLimitAuditSamples: [UUID: [RateLimitAuditSample]] = [:]
    var notificationPermissionGate = NotificationPermissionGate()

    enum AddingStep { case idle, waitingLogin, confirmProfile, done }

    // MARK: - Init

    private init() {
        profileManager.bootstrap()
        let recoveryResult = profileManager.verifyAndRecoverActiveAuth()
        if recoveryResult == .unrecoverable { }
        loadProfiles()
        switchHistory = historyStore.load()
        switchTimeline = switchTimelineStore.load()
        switchDecisionHistory = switchDecisionStore.load()
        refreshReliabilityAnalytics()

        usageMonitor.onRateLimit = { [weak self] in
            Task { @MainActor in self?.handleRateLimitDetected() }
        }
        usageMonitor.onTokenUpdate = { [weak self] in
            self?.scheduleTokenRefresh()
        }
        usageMonitor.onSessionActivity = { [weak self] in
            Task { @MainActor in self?.recordSessionActivity() }
        }
        usageMonitor.start()
        startUsagePolling()
        startRateLimitPolling()
        startAutomationHealthPolling()
        refreshTokenUsage()
        syncSwitchOrchestrationState()
    }

    // MARK: - Update Checker

    func checkForUpdates() {
        Task {
            let prior = updateStatus
            await MainActor.run {
                self.updateStatus = .checking(
                    currentVersion: prior.currentVersion,
                    latestVersion: prior.latestVersion,
                    release: prior.release,
                    lastCheckedAt: prior.lastCheckedAt
                )
            }
            let snapshot = await UpdateChecker.check()
            await MainActor.run { self.updateStatus = snapshot }
            if let release = snapshot.release, snapshot.state == .updateAvailable {
                sendNotification(
                    title: L("Güncelleme mevcut", "Update available"),
                    body: "CodexSwitcher \(release.version)"
                )
            }
        }
    }

    func checkForUpdatesManually() {
        Task {
            let prior = updateStatus
            await MainActor.run {
                self.updateStatus = .checking(
                    currentVersion: prior.currentVersion,
                    latestVersion: prior.latestVersion,
                    release: prior.release,
                    lastCheckedAt: prior.lastCheckedAt
                )
            }
            let snapshot = await UpdateChecker.check()
            await MainActor.run {
                self.updateStatus = snapshot
                self.openReleasePage()
            }
        }
    }

    func openReleasePage() {
        if let url = updateStatus.release?.releaseURL {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "https://github.com/senoldogann/codex-switcher/releases")!)
        }
    }

    // MARK: - Usage Polling

    private func startUsagePolling() {
        refreshActiveTurns()
        usageTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshActiveTurns() }
        }
    }

    func refreshActiveTurns() {
        guard let profile = activeProfile, let activatedAt = profile.activatedAt else {
            activeTurns = usageTracker.turnsInLast(hours: 5)
            return
        }
        activeTurns = usageTracker.turnsSince(activatedAt)
    }

    private func captureUsageForActive() {
        guard let active = activeProfile else { return }
        var config = profileManager.loadConfig()
        guard let idx = config.profiles.firstIndex(where: { $0.id == active.id }) else { return }
        config.profiles[idx].lastKnownTurns = activeTurns
        profileManager.saveConfig(config)
        profiles = config.profiles
    }

    // MARK: - Profile Loading

    func loadProfiles() {
        var config = profileManager.loadConfig()
        profiles = config.profiles
        if let id = config.activeProfileId {
            activeProfile = profiles.first { $0.id == id }
        } else if let first = profiles.first {
            activeProfile = first
            config.activeProfileId = first.id
            profileManager.saveConfig(config)
        }
    }

    func setAnalyticsTimeRange(_ range: AnalyticsTimeRange) {
        guard analyticsTimeRange != range else { return }
        analyticsTimeRange = range
        analyticsSnapshot = .empty(for: range)
        refreshTokenUsage()
    }

    func openAnalyticsWindow() {
        if let window = analyticsWindow, window.isVisible {
            window.makeKeyAndOrderFront(NSApp)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingView(rootView: AnalyticsWindowView().environmentObject(self))
        hosting.frame = NSRect(x: 0, y: 0, width: 1040, height: 780)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L("Analitik", "Analytics")
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 920, height: 680)
        let isDark = UserDefaults.standard.object(forKey: "isDarkMode") as? Bool ?? true
        window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        window.backgroundColor = isDark
            ? NSColor.black.withAlphaComponent(0.82)
            : NSColor.white.withAlphaComponent(0.88)
        window.center()
        window.makeKeyAndOrderFront(NSApp)
        NSApp.activate(ignoringOtherApps: true)
        analyticsWindow = window
    }

    // MARK: - Token / Rate Limit Accessors

    func getTokenUsage(for profile: Profile) -> AccountTokenUsage? { tokenUsage[profile.id] }
    func rateLimit(for profile: Profile) -> RateLimitInfo? { rateLimits[profile.id] }

    var nextResetInfo: (profileName: String, resetTime: String)? {
        let exhaustedProfiles = profiles.filter { rateLimits[$0.id]?.limitReached == true }
        let resetTimes = exhaustedProfiles.compactMap { profile -> (String, Date)? in
            let rl = rateLimits[profile.id]
            let candidates = [rl?.weeklyResetAt, rl?.fiveHourResetAt].compactMap { $0 }
            guard let earliest = candidates.min() else { return nil }
            return (profile.displayName, earliest)
        }
        guard let (name, date) = resetTimes.min(by: { $0.1 < $1.1 }) else { return nil }
        let fmt = DateFormatter()
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(date)
        fmt.dateFormat = isToday ? "HH:mm" : "d MMM HH:mm"
        return (name, fmt.string(from: date))
    }

    // MARK: - Smart Switch

    func smartNextProfile(auto: Bool) -> Profile? {
        let evaluation = makeSwitchReadinessEvaluation()
        let preferredId: UUID?
        if auto {
            preferredId = evaluation.candidates.first(where: { $0.status == .ready })?.profileId
                ?? evaluation.preferredCandidateId
        } else {
            preferredId = evaluation.preferredCandidateId
        }
        guard let preferredId else { return nil }
        return profiles.first { $0.id == preferredId }
    }

    // MARK: - Switching

    func switchToNext(reason: String = L("Manuel geçiş", "Manual switch")) {
        captureUsageForActive()
        let isAuto = reason.contains(L("Limit", "Limit"))
        guard let candidate = smartNextProfile(auto: isAuto) else {
            if isAuto {
                recordSwitchDecision(
                    requestedProfile: nil,
                    chosenProfile: nil,
                    source: .automatic,
                    outcome: .halted,
                    reason: reason,
                    detail: L("Güvenli hedef bulunamadı.", "No safe target was available."),
                    overrideApplied: false
                )
                switchOrchestrator.recordHaltedDecision(
                    reason: reason,
                    detail: L("Hiçbir hesap güvenli hedef olarak seçilemedi.", "No account qualified as a safe switch target.")
                )
                syncSwitchOrchestrationState()
            }
            allExhausted = true
            sendNotification(title: Str.allExhausted, body: L("Limitler sıfırlanınca devam eder.", "Will resume when limits reset."))
            return
        }
        activateCandidate(candidate, reason: reason, source: isAuto ? .automatic : .manual, overrideApplied: false)
    }

    func switchTo(profile: Profile) {
        captureUsageForActive()
        let evaluation = makeSwitchReadinessEvaluation()
        let readiness = evaluation.candidates.first(where: { $0.profileId == profile.id })
        let isSafe = readiness?.status == .ready || readiness?.status == .warning
        guard isSafe else {
            recordSwitchDecision(
                requestedProfile: profile,
                chosenProfile: profile,
                source: .manual,
                outcome: .manualOverride,
                reason: L("Manuel seçim", "Manual selection"),
                detail: manualSwitchBlockedMessage(for: profile, rateLimit: rateLimits[profile.id]),
                overrideApplied: true,
                evaluation: evaluation
            )
            switchOrchestrator.recordBlockedDecision(
                targetProfileName: profile.displayName,
                reason: L("Manuel override", "Manual override"),
                detail: L(
                    "Güvensiz hedef uyarı ile seçildi; manuel override uygulandı.",
                    "Unsafe target was selected with a warning; manual override was applied."
                )
            )
            syncSwitchOrchestrationState()
            sendNotification(
                title: L("Dikkatli geçiş", "Proceeding with caution"),
                body: manualSwitchBlockedMessage(for: profile, rateLimit: rateLimits[profile.id])
            )
            switchTo(profile: profile, reason: L("Manuel override", "Manual override"), source: .manual, overrideApplied: true)
            return
        }
        switchTo(profile: profile, reason: L("Manuel seçim", "Manual selection"), source: .manual, overrideApplied: false)
    }

    func switchTo(profile: Profile, reason: String) {
        switchTo(profile: profile, reason: reason, source: .manual, overrideApplied: false)
    }

    func switchTo(
        profile: Profile,
        reason: String,
        source: SwitchDecisionSource,
        overrideApplied: Bool
    ) {
        activateCandidate(profile, reason: reason, source: source, overrideApplied: overrideApplied)
    }

    private func activateCandidate(
        _ candidate: Profile,
        reason: String,
        source: SwitchDecisionSource,
        overrideApplied: Bool
    ) {
        // NOTE: history is written in finalizeActivation, NOT here.
        // Writing before we know activation succeeded would permanently corrupt analytics
        // attribution (the parser treats history as authoritative for token ownership).
        let evaluation = makeSwitchReadinessEvaluation()
        do {
            lastAuthWriteDate = Date()
            let verifyResult = try profileManager.activate(profile: candidate)

            switch verifyResult {
            case .verified:
                finalizeActivation(
                    candidate,
                    reason: reason,
                    source: source,
                    overrideApplied: overrideApplied,
                    evaluation: evaluation
                )
            case .failed:
                let retryResult = profileManager.verifyActiveAccount(expectedAccountId: candidate.accountId)
                switch retryResult {
                case .verified:
                    finalizeActivation(
                        candidate,
                        reason: reason,
                        source: source,
                        overrideApplied: overrideApplied,
                        evaluation: evaluation
                    )
                case .failed:
                    recordSwitchDecision(
                        requestedProfile: candidate,
                        chosenProfile: candidate,
                        source: source,
                        outcome: .blocked,
                        reason: reason,
                        detail: L("Hesap doğrulanamadı.", "Account verification failed."),
                        overrideApplied: overrideApplied,
                        evaluation: evaluation
                    )
                    switchOrchestrator.recordBlockedDecision(
                        targetProfileName: candidate.displayName,
                        reason: reason,
                        detail: L("Hedef hesap doğrulanamadı.", "Target account could not be verified.")
                    )
                    syncSwitchOrchestrationState()
                    sendNotification(
                        title: L("Geçiş başarısız", "Switch failed"),
                        body: L("Hesap doğrulanamadı. Lütfen tekrar deneyin.", "Account verification failed. Please try again.")
                    )
                }
            }
        } catch {
            recordSwitchDecision(
                requestedProfile: candidate,
                chosenProfile: candidate,
                source: source,
                outcome: .blocked,
                reason: reason,
                detail: error.localizedDescription,
                overrideApplied: overrideApplied,
                evaluation: evaluation
            )
            switchOrchestrator.recordBlockedDecision(
                targetProfileName: candidate.displayName,
                reason: reason,
                detail: error.localizedDescription
            )
            syncSwitchOrchestrationState()
            sendNotification(title: L("Geçiş başarısız", "Switch failed"), body: error.localizedDescription)
        }
    }

    private func manualSwitchBlockedMessage(for profile: Profile, rateLimit: RateLimitInfo?) -> String {
        guard let rateLimit else {
            return L(
                "\(profile.displayName) için güncel limit verisi yok.",
                "No current limit data is available for \(profile.displayName)."
            )
        }
        let weeklyRemaining  = max(0, 100 - (rateLimit.weeklyUsedPercent ?? 100))
        let fiveHourRemaining = rateLimit.fiveHourRemainingPercent ?? 0
        return L(
            "\(profile.displayName) güvenli değil. Haftalık kalan %\(weeklyRemaining), 5 saatlik kalan %\(fiveHourRemaining).",
            "\(profile.displayName) is not safe to switch into. Weekly remaining \(weeklyRemaining)%, 5-hour remaining \(fiveHourRemaining)%."
        )
    }

    private func finalizeActivation(
        _ candidate: Profile,
        reason: String,
        source: SwitchDecisionSource,
        overrideApplied: Bool,
        evaluation: SwitchReadinessEvaluation
    ) {
        // Write history ONLY after verified activation to keep analytics attribution clean.
        let event = SwitchEvent(
            id: UUID(),
            timestamp: Date(),
            fromAccountName: activeProfile?.displayName,
            fromAccountId: activeProfile?.id,
            toAccountName: candidate.displayName,
            toAccountId: candidate.id,
            reason: reason
        )
        historyStore.append(event)
        switchHistory = historyStore.load()
        recordSwitchDecision(
            requestedProfile: candidate,
            chosenProfile: candidate,
            source: source,
            outcome: overrideApplied ? .manualOverride : .executed,
            reason: reason,
            detail: L("Hedef hesap doğrulandı ve aktif edildi.", "Target account was verified and activated."),
            overrideApplied: overrideApplied,
            evaluation: evaluation
        )

        var config = profileManager.loadConfig()
        if let i = config.profiles.firstIndex(where: { $0.id == candidate.id }) {
            config.profiles[i].activatedAt = Date()
        }
        config.activeProfileId = candidate.id
        profileManager.saveConfig(config)

        let newActiveProfile = config.profiles.first { $0.id == candidate.id }
        activeProfile = newActiveProfile
        profiles = config.profiles
        allExhausted = false
        activeTurns = 0

        refreshTokenUsage()
        notifyProfileChanged()
        sendNotification(title: L("Hesap değiştirildi", "Account switched"), body: "\(candidate.displayName) — \(reason)")
        Task { await fetchAllRateLimits() }
        attemptSeamlessSwitch(for: candidate)
    }

    func makeSwitchReadinessEvaluation() -> SwitchReadinessEvaluation {
        SwitchReadinessEvaluator(policy: switchDecisionPolicy).evaluate(
            profiles: profiles,
            activeProfileId: activeProfile?.id,
            rateLimits: rateLimits,
            staleProfileIds: staleProfileIds
        )
    }

    func recordSwitchDecision(
        requestedProfile: Profile?,
        chosenProfile: Profile?,
        source: SwitchDecisionSource,
        outcome: SwitchDecisionOutcome,
        reason: String,
        detail: String,
        overrideApplied: Bool,
        evaluation: SwitchReadinessEvaluation? = nil
    ) {
        let record = SwitchDecisionRecord(
            id: UUID(),
            timestamp: Date(),
            source: source,
            outcome: outcome,
            requestedProfileId: requestedProfile?.id,
            requestedProfileName: requestedProfile?.displayName,
            chosenProfileId: chosenProfile?.id,
            chosenProfileName: chosenProfile?.displayName,
            reason: reason,
            detail: detail,
            overrideApplied: overrideApplied,
            readiness: (evaluation ?? makeSwitchReadinessEvaluation()).candidates
        )
        switchDecisionStore.append(record)
        switchDecisionHistory = switchDecisionStore.load()
    }

    // MARK: - AI Restart

    func restartAIIfRunning(for profile: Profile) {
        restartCodexIfRunning()
    }

    private func restartCodexIfRunning() {
        guard let codexApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == "Codex" && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }) else { return }

        let bundleURL = codexApp.bundleURL
        codexApp.forceTerminate()

        sendNotification(
            title: L("Hesap değiştirildi", "Account Switched"),
            body: L("Codex yeniden başlatılıyor. Yeni hesap aktif.", "Codex is restarting. New account is now active.")
        )

        guard let url = bundleURL else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
        }
    }

    // MARK: - Rate Limit Detection

    func handleRateLimitDetected() {
        guard !allExhausted, !rateLimitCheckPending else { return }
        if let last = lastAutoSwitchDate,
           Date().timeIntervalSince(last) < Self.switchCooldown { return }

        rateLimitCheckPending = true
        Task {
            await fetchAllRateLimits(showSpinner: false)
            rateLimitCheckPending = false

            guard let activeId = activeProfile?.id else { return }

            if let rl = rateLimits[activeId] {
                guard self.switchDecisionPolicy.shouldLeaveCurrentProfile(rl) else { return }
            }

            if self.switchOrchestrationState == .verifying {
                self.handleSeamlessVerificationFailure()
                return
            }

            lastAutoSwitchDate = Date()
            let reason = self.automaticSwitchReason(for: self.rateLimits[activeId])
            if self.isSessionActive {
                self.queuePendingSwitch(reason: reason)
                return
            }
            self.switchToNext(reason: reason)
        }
    }

    func evaluateAutomaticSwitchAfterRateLimitRefresh() {
        guard !allExhausted,
              let activeId = activeProfile?.id,
              let activeRateLimit = rateLimits[activeId],
              switchDecisionPolicy.shouldLeaveCurrentProfile(activeRateLimit) else { return }
        if let last = lastAutoSwitchDate,
           Date().timeIntervalSince(last) < Self.switchCooldown { return }
        if switchOrchestrationState == .verifying {
            handleSeamlessVerificationFailure()
            return
        }

        let reason = automaticSwitchReason(for: activeRateLimit)
        lastAutoSwitchDate = Date()
        if isSessionActive {
            queuePendingSwitch(reason: reason)
            return
        }
        switchToNext(reason: reason)
    }

    // MARK: - Helpers

    func notifyProfileChanged() {
        NotificationCenter.default.post(name: .profileChanged, object: nil)
    }

    private func automaticSwitchReason(for rateLimit: RateLimitInfo?) -> String {
        switch switchDecisionPolicy.automaticReasonKind(for: rateLimit) {
        case .limitReached:   return L("Limit doldu", "Limit reached")
        case .fiveHourPressure: return L("5 saatlik limit kritik seviyede", "5-hour limit is critically low")
        case .weeklyPressure:  return L("Haftalık limit kritik seviyede", "Weekly limit is critically low")
        case nil:             return L("Limit kritik seviyede", "Limit is critically low")
        }
    }

    func requestNotificationPermissionIfNeeded() {
        notificationPermissionGate.runIfNeeded {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func sendNotification(title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        )
    }
}
