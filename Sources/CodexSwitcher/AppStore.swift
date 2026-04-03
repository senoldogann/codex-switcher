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
    @Published var pendingProfileEmail: String = ""
    @Published var aliasText: String = ""
    @Published var allExhausted: Bool = false
    @Published var activeTurns: Int = 0
    @Published var rateLimits: [UUID: RateLimitInfo] = [:]
    @Published var isFetchingLimits: Bool = false
    @Published var switchHistory: [SwitchEvent] = []
    @Published var tokenUsage: [UUID: AccountTokenUsage] = [:]
    @Published var staleProfileIds: Set<UUID> = []
    @Published var costs: [UUID: Double] = [:]
    @Published var forecasts: [UUID: RateLimitForecast] = [:]
    @Published var dailyUsage: [UUID: [DailyUsage]] = [:]
    @Published var lastKnownLimitState: [UUID: Bool] = [:]  // track for restored notifications
    @Published var isSessionActive: Bool = false  // live session indicator

    @Published var availableUpdate: UpdateChecker.Release? = nil
    @Published var pendingProvider: AIProvider = .codex

    @Published var projectUsage: [ProjectUsage] = []
    @Published var sessionSummaries: [SessionSummary] = []
    @Published var hourlyActivity: [HourlyActivity] = []
    @Published var expensiveTurns: [ExpensiveTurn] = []

    private var lastBudgetAlertDate: Date?
    private var lastWeeklySummaryDate: Date?
    private var claudeAuthPoller: Timer?

    func checkForUpdates() {
        Task {
            let release = await UpdateChecker.fetchIfNewer()
            await MainActor.run { self.availableUpdate = release }
            if let release {
                sendNotification(
                    title: L("Güncelleme mevcut", "Update available"),
                    body: "CodexSwitcher \(release.version)"
                )
            }
        }
    }

    /// Called when the user manually taps the Update button.
    /// Checks for updates and always opens the releases page (shows feedback even when up to date).
    func checkForUpdatesManually() {
        Task {
            let release = await UpdateChecker.fetchIfNewer()
            await MainActor.run {
                self.availableUpdate = release
                // Always open releases page so the user sees something happened
                self.openReleasePage()
            }
        }
    }

    func openReleasePage() {
        if let url = availableUpdate?.releaseURL {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "https://github.com/senoldogann/codex-switcher/releases")!)
        }
    }

    static let turnsLimit = 50
    static let switchCooldown: TimeInterval = 60   // otomatik geçiş arası min süre (sn)

    private let profileManager = ProfileManager()
    private let usageMonitor = UsageMonitor()
    private let usageTracker = SessionUsageTracker()
    private let fetcher = RateLimitFetcher()
    private let historyStore = SwitchHistoryStore()
    private let tokenParser = SessionTokenParser()
    private var usageTimer: Timer?
    private var rateLimitTimer: Timer?
    private var authWatcher: DispatchSourceFileSystemObject?
    private var authWatcherFd: Int32 = -1
    private var loginTimeout: DispatchWorkItem?
    private var lastAutoSwitchDate: Date?
    private var rateLimitCheckPending = false
    private var lastAuthWriteDate: Date?
    private var consecutiveFetchFailures: Int = 0
    private var paceHistory: [SessionPacePoint] = []
    private var tokenRefreshWork: DispatchWorkItem?
    private var warned80PercentIds: Set<UUID> = []
    private var reloginTargetId: UUID? = nil

    enum AddingStep { case idle, waitingLogin, confirmProfile, done }

    // MARK: - Init

    private init() {
        profileManager.bootstrap()
        let recoveryResult = profileManager.verifyAndRecoverActiveAuth()
        if recoveryResult == .unrecoverable {
            // All profiles will show as stale; user needs to re-login
        }
        loadProfiles()
        switchHistory = historyStore.load()
        requestNotificationPermission()

        usageMonitor.onRateLimit = { [weak self] in
            Task { @MainActor in self?.handleRateLimitDetected() }
        }
        usageMonitor.onTokenUpdate = { [weak self] in
            self?.scheduleTokenRefresh()
        }
        usageMonitor.onSessionActivity = { [weak self] in
            Task { @MainActor in
                self?.isSessionActive = true
                // Reset after 5 seconds of no activity
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self?.isSessionActive = false
                }
            }
        }
        usageMonitor.start()
        startUsagePolling()
        startRateLimitPolling()
        refreshTokenUsage()
    }

    // MARK: - Rate Limit Polling

    private func startRateLimitPolling() {
        // İlk fetch hemen yap (status bar'ın veri göstermesi için)
        Task { await fetchAllRateLimits(showSpinner: false) }
        // Arka planda her 5 dakikada sessizce güncelle (60s çok sıktı, pil tüketiyordu)
        rateLimitTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.fetchAllRateLimits(showSpinner: false) }
        }
    }

    /// Token refresh'i debounce eder — aktif session'da her yazımda değil, 10s sessizlik sonra çalışır.
    private func scheduleTokenRefresh() {
        tokenRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshTokenUsage() }
        tokenRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    // MARK: - Rate Limit Fetch (tüm hesaplar için)

    func fetchAllRateLimits(showSpinner: Bool = true) async {
        if showSpinner { isFetchingLimits = true }
        defer { if showSpinner { isFetchingLimits = false } }

        let fetcher = self.fetcher

        let activeProfileId = activeProfile?.id
        let credPairs: [(UUID, AuthCredentials)] = profiles.compactMap { profile in
            // Claude Code profiles use a different auth system — skip Codex rate limit API
            guard profile.aiProvider == .codex else { return nil }
            // Aktif hesap için her zaman live ~/.codex/auth.json'u kullan (en güncel token)
            let dict: [String: Any]?
            if profile.id == activeProfileId,
               let liveDict = profileManager.readLiveAuthDict() {
                dict = liveDict
            } else {
                dict = profileManager.readAuthDict(for: profile)
            }
            guard let dict = dict,
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
            case .success(let info):
                rateLimits[id] = info
                successCount += 1
                let profileName = profiles.first(where: { $0.id == id })?.displayName ?? L("Hesap", "Account")
                // Restored notification
                if lastKnownLimitState[id] == true, info.limitReached == false {
                    sendNotification(
                        title: L("Limit sıfırlandı", "Limit reset"),
                        body: L("\(profileName) kullanıma hazır", "\(profileName) is ready to use again")
                    )
                    warned80PercentIds.remove(id) // reset warning for next cycle
                }
                lastKnownLimitState[id] = info.limitReached
                // %80 uyarısı — henüz uyarılmamışsa ve limit dolmamışsa
                if let used = info.weeklyUsedPercent,
                   used >= 80, !info.limitReached,
                   !warned80PercentIds.contains(id) {
                    warned80PercentIds.insert(id)
                    sendNotification(
                        title: L("Limit uyarısı", "Limit warning"),
                        body: L("\(profileName) haftalık limitinin %\(100 - used)'i kaldı", "\(profileName) has \(100 - used)% weekly limit remaining")
                    )
                }
            case .stale:
                newStale.insert(id)
            case .failure:
                break
            }
        }

        // Consecutive failure gating
        if successCount == 0 && !credPairs.isEmpty {
            consecutiveFetchFailures += 1
            if consecutiveFetchFailures >= 3 {
                // Back off: skip next few polls
                return
            }
        } else {
            consecutiveFetchFailures = 0
        }

        staleProfileIds = newStale
        NotificationCenter.default.post(name: .rateLimitsUpdated, object: nil)
        refreshTokenUsage()
        // Note: updateCostsAndForecasts is called within refreshTokenUsage after async completion
    }

    func refreshTokenUsage() {
        let profiles = self.profiles
        let history  = self.switchHistory
        let parser   = self.tokenParser
        let activeProfileId = self.activeProfile?.id
        DispatchQueue.global(qos: .utility).async {
            let result   = parser.calculate(profiles: profiles, history: history, activeProfileId: activeProfileId)
            let daily    = parser.calculateDaily(profiles: profiles, history: history, activeProfileId: activeProfileId)
            let insights = parser.calculateInsights()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard self.profiles.count == profiles.count else { return }
                self.tokenUsage       = result
                self.dailyUsage       = daily
                self.projectUsage     = insights.projects
                self.sessionSummaries = insights.sessions
                self.hourlyActivity   = insights.hourlyActivity
                self.expensiveTurns   = insights.expensiveTurns
                self.updateCostsAndForecasts(profiles: profiles)
            }
        }
    }

    private func updateCostsAndForecasts(profiles: [Profile]) {
        let calculator = CostCalculator()
        var newCosts: [UUID: Double] = [:]
        var newForecasts: [UUID: RateLimitForecast] = [:]

        for profile in profiles {
            if let usage = tokenUsage[profile.id] {
                newCosts[profile.id] = calculator.cost(for: usage)
            }
            newForecasts[profile.id] = RateLimitForecaster.forecast(
                profileId: profile.id,
                rateLimit: rateLimits[profile.id],
                tokenUsage: tokenUsage[profile.id],
                sessionHistory: paceHistory
            )
        }

        costs = newCosts
        forecasts = newForecasts

        checkBudget(costs: newCosts)
        checkWeeklySummary(costs: newCosts)

        // Update pace history
        let totalTokens = tokenUsage.values.reduce(0) { $0 + $1.totalTokens }
        if totalTokens > 0 {
            paceHistory.append(SessionPacePoint(timestamp: Date(), cumulativeTokens: totalTokens))
            // Keep last 24 hours of data points
            let cutoff = Date().addingTimeInterval(-24 * 3600)
            paceHistory.removeAll { $0.timestamp < cutoff }
        }
    }

    // MARK: - Budget Alert

    private func checkBudget(costs: [UUID: Double]) {
        let limit = UserDefaults.standard.double(forKey: "weeklyBudgetUSD")
        guard limit > 0 else { return }
        let total = costs.values.reduce(0, +)
        guard total >= limit else { return }
        let today = Calendar.current.startOfDay(for: Date())
        if let last = lastBudgetAlertDate, Calendar.current.startOfDay(for: last) == today { return }
        lastBudgetAlertDate = Date()
        let spent = String(format: "%.2f", total)
        let cap   = String(format: "%.2f", limit)
        sendNotification(
            title: L("Bütçe aşıldı 💸", "Budget exceeded 💸"),
            body:  L("Bu hafta $\(spent) harcandı (limit: $\(cap))",
                     "Spent $\(spent) this week (budget: $\(cap))")
        )
    }

    // MARK: - Weekly Summary (Sunday evening)

    private func checkWeeklySummary(costs: [UUID: Double]) {
        let cal  = Calendar.current
        let now  = Date()
        let comps = cal.dateComponents([.weekday, .hour], from: now)
        // Sunday = weekday 1 in Gregorian; send after 18:00
        guard comps.weekday == 1, (comps.hour ?? 0) >= 18 else { return }
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        if let last = lastWeeklySummaryDate, last > weekStart { return }
        lastWeeklySummaryDate = now

        let totalCost   = costs.values.reduce(0, +)
        let totalTokens = tokenUsage.values.reduce(0) { $0 + $1.totalTokens }
        let topProject  = projectUsage.first?.name ?? "—"

        func fmt(_ n: Int) -> String {
            n >= 1_000_000 ? String(format: "%.1fM", Double(n)/1_000_000)
          : n >= 1_000     ? String(format: "%.1fK", Double(n)/1_000)
          : "\(n)"
        }
        sendNotification(
            title: L("Haftalık Özet 📊", "Weekly Summary 📊"),
            body:  L("\(fmt(totalTokens)) token · $\(String(format:"%.2f",totalCost)) · \(topProject)",
                     "\(fmt(totalTokens)) tokens · $\(String(format:"%.2f",totalCost)) · top: \(topProject)")
        )
    }

    func getTokenUsage(for profile: Profile) -> AccountTokenUsage? {
        tokenUsage[profile.id]
    }

    func rateLimit(for profile: Profile) -> RateLimitInfo? {
        rateLimits[profile.id]
    }

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

    // MARK: - Smart Switch

    /// Rate limit verisine göre en iyi hesabı seçer.
    /// Auto modda tüm hesaplar tükenirse nil döner → allExhausted tetiklenir.
    private func smartNextProfile(auto: Bool) -> Profile? {
        let candidates = profiles.filter { $0.id != activeProfile?.id }
        guard !candidates.isEmpty else { return nil }

        if auto {
            // Kullanılabilir hesaplar: veri yoksa optimistik (bilinmiyor = dene),
            // veri varsa limitReached=false VE weekly < 100
            let available = candidates.filter { profile in
                guard let rl = rateLimits[profile.id] else { return true } // veri yok → dene
                return !rl.limitReached && (rl.weeklyUsedPercent ?? 0) < 100
            }

            // Hiç kullanılabilir hesap yoksa → allExhausted
            guard !available.isEmpty else { return nil }

            // En düşük haftalık kullanımlı hesabı seç (veri yoksa 0 say)
            return available.min {
                (rateLimits[$0.id]?.weeklyUsedPercent ?? 0) < (rateLimits[$1.id]?.weeklyUsedPercent ?? 0)
            }
        }

        // Manuel geçiş: round-robin
        let currentIndex = profiles.firstIndex { $0.id == activeProfile?.id } ?? -1
        return candidates.first {
            profiles.firstIndex(of: $0) == (currentIndex + 1) % profiles.count
        } ?? candidates.first
    }

    // MARK: - Switching

    func switchToNext(reason: String = L("Manuel geçiş", "Manual switch")) {
        captureUsageForActive()
        let isAuto = reason.contains(L("Limit", "Limit"))
        guard let candidate = smartNextProfile(auto: isAuto) else {
            allExhausted = true
            sendNotification(title: Str.allExhausted, body: L("Limitler sıfırlanınca devam eder.", "Will resume when limits reset."))
            return
        }
        activateCandidate(candidate, reason: reason)
    }

    func switchTo(profile: Profile) {
        captureUsageForActive()
        activateCandidate(profile, reason: L("Manuel seçim", "Manual selection"))
    }

    private func activateCandidate(_ candidate: Profile, reason: String) {
        // Switch event'ini kaydet
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

        do {
            lastAuthWriteDate = Date() // debounce: prevent authFileChanged from firing
            let verifyResult = try profileManager.activate(profile: candidate)

            switch verifyResult {
            case .verified:
                finalizeActivation(candidate, reason: reason)
            case .failed:
                // One retry: re-read file (in case of race with external writer)
                let retryResult = profileManager.verifyActiveAccount(expectedAccountId: candidate.accountId)
                switch retryResult {
                case .verified:
                    finalizeActivation(candidate, reason: reason)
                case .failed:
                    sendNotification(
                        title: L("Geçiş başarısız", "Switch failed"),
                        body: L("Hesap doğrulanamadı. Lütfen tekrar deneyin.", "Account verification failed. Please try again.")
                    )
                }
            }
        } catch {
            sendNotification(title: L("Geçiş başarısız", "Switch failed"), body: error.localizedDescription)
        }
    }

    private func finalizeActivation(_ candidate: Profile, reason: String) {
        var config = profileManager.loadConfig()
        if let i = config.profiles.firstIndex(where: { $0.id == candidate.id }) {
            config.profiles[i].activatedAt = Date()
        }
        config.activeProfileId = candidate.id
        profileManager.saveConfig(config)
        
        // Update state atomically
        let newActiveProfile = config.profiles.first { $0.id == candidate.id }
        activeProfile = newActiveProfile
        profiles = config.profiles
        allExhausted = false
        activeTurns = 0
        
        // Refresh token usage with updated history
        refreshTokenUsage()
        
        notifyProfileChanged()
        sendNotification(title: L("Hesap değiştirildi", "Account switched"), body: "\(candidate.displayName) — \(reason)")
        Task { await fetchAllRateLimits() }
        restartAIIfRunning(for: candidate)
    }

    // MARK: - AI Restart

    private func restartAIIfRunning(for profile: Profile) {
        switch profile.aiProvider {
        case .codex:      restartCodexIfRunning()
        case .claudeCode: notifyClaudeSessionRestart()
        }
    }

    /// Claude Code is a CLI — notify user to restart their session.
    private func notifyClaudeSessionRestart() {
        sendNotification(
            title: L("Claude kimlik bilgileri güncellendi", "Claude credentials updated"),
            body:  L("Aktif claude oturumlarını yeniden başlatın.", "Please restart any active claude sessions.")
        )
    }

    private func restartCodexIfRunning() {
        guard let codexApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == "Codex" && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }) else { return }

        // Capture URL before killing — becomes inaccessible after process dies
        let bundleURL = codexApp.bundleURL

        // forceTerminate = SIGKILL, no confirmation dialog, instant
        codexApp.forceTerminate()

        sendNotification(
            title: L("Hesap değiştirildi", "Account Switched"),
            body: L("Codex yeniden başlatılıyor. Yeni hesap aktif.", "Codex is restarting. New account is now active.")
        )

        guard let url = bundleURL else { return }
        // 1s is enough after force kill (no graceful shutdown to wait for)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in }
        }
    }

    // MARK: - Rename

    func renameProfile(_ profile: Profile, alias: String) {
        var config = profileManager.loadConfig()
        guard let i = config.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        config.profiles[i].alias = alias
        profileManager.saveConfig(config)
        profiles = config.profiles
        if activeProfile?.id == profile.id {
            activeProfile = config.profiles[i]
            notifyProfileChanged()
        }
    }

    func showRenameDialog(for profile: Profile) {
        let alert = NSAlert()
        alert.messageText = Str.renameTitle
        alert.informativeText = profile.email
        alert.addButton(withTitle: Str.save)
        alert.addButton(withTitle: Str.cancel)

        // Use Codex icon instead of blank app icon
        if let url = Bundle.appResources.url(forResource: "codex", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            alert.icon = icon
        }

        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        tf.stringValue = profile.alias
        tf.placeholderString = profile.email
        tf.bezelStyle = .roundedBezel
        alert.accessoryView = tf

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newAlias = tf.stringValue.trimmingCharacters(in: .whitespaces)
            renameProfile(profile, alias: newAlias)
        }
    }

    func handleRateLimitDetected() {
        // UsageMonitor keyword tespiti yanlış pozitif olabilir (kod içindeki "rate_limit" stringleri,
        // geçici per-request 429 hataları vb.). Gerçekten limiti dolduğunu API'den doğrula.
        guard !allExhausted, !rateLimitCheckPending else { return }
        if let last = lastAutoSwitchDate,
           Date().timeIntervalSince(last) < Self.switchCooldown { return }

        rateLimitCheckPending = true
        Task {
            await fetchAllRateLimits(showSpinner: false)
            rateLimitCheckPending = false

            guard let activeId = activeProfile?.id else { return }

            if let rl = rateLimits[activeId] {
                // Güncel API verisi var — sadece gerçekten limitdeyse geç
                guard rl.limitReached else { return }
            }
            // Hesap verisi yoksa (API başarısız) → ihtiyatlı olarak geç

            lastAutoSwitchDate = Date()
            switchToNext(reason: L("Limit doldu", "Limit reached"))
        }
    }

    // MARK: - Add Account

    private var addAccountWindow: NSWindow?

    func openAddAccountWindow() {
        addingStep = .idle
        isAddingAccount = false
        pendingProfileEmail = ""
        aliasText = ""

        if let w = addAccountWindow, w.isVisible {
            w.makeKeyAndOrderFront(NSApp)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingView(rootView: AddAccountView().environmentObject(self))
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 320)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        let isDark = UserDefaults.standard.object(forKey: "isDarkMode") as? Bool ?? true
        window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        window.backgroundColor = isDark
            ? NSColor.black.withAlphaComponent(0.85)
            : NSColor.white.withAlphaComponent(0.85)
        window.center()
        window.makeKeyAndOrderFront(NSApp)
        NSApp.activate(ignoringOtherApps: true)
        addAccountWindow = window
    }

    func closeAddAccountWindow() { addAccountWindow?.close() }

    func beginAddAccount(provider: AIProvider = .codex) {
        pendingProvider = provider
        isAddingAccount = true
        addingStep = .waitingLogin

        switch provider {
        case .codex:
            openTerminalWithCodexLogin()
            watchAuthFileForNewLogin()
        case .claudeCode:
            openTerminalWithClaudeLogin()
            let previousData = ClaudeCodeManager.readCredentialsData()
            startClaudeKeychainPoller(previousData: previousData)
        }

        cancelLoginTimeout()
        let timeout = DispatchWorkItem { [weak self] in self?.loginTimedOut() }
        loginTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: timeout)
    }

    private func openTerminalWithClaudeLogin() {
        // claude auth login is interactive — must run inside a visible Terminal window.
        // Use the shell's login environment so user PATH (~/.local/bin, /opt/homebrew/bin, etc.) is resolved.
        let script = """
        tell application "Terminal"
            activate
            do script "claude auth login"
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
    }

    /// Finds a CLI binary using the user's login shell PATH.
    /// Falls back through common install locations if the shell lookup fails.
    private func findCLIPath(_ name: String) -> String {
        // Use zsh login shell so ~/.zprofile / ~/.zshrc paths (Homebrew, npm, etc.) are loaded
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-l", "-c", "which \(name)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = nil
        try? task.run()
        task.waitUntilExit()
        let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty { return raw }

        // Common install locations as fallback
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.npm-global/bin/\(name)"
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? "/usr/local/bin/\(name)"
    }

    private func startClaudeKeychainPoller(previousData: Data?) {
        claudeAuthPoller?.invalidate()
        claudeAuthPoller = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let newData = ClaudeCodeManager.readCredentialsData() else { return }
            if newData != previousData {
                self.claudeAuthPoller?.invalidate()
                self.claudeAuthPoller = nil
                self.claudeKeychainUpdated(data: newData)
            }
        }
    }

    private func claudeKeychainUpdated(data: Data) {
        guard addingStep == .waitingLogin else { return }
        // Claude Code uses opaque (non-JWT) tokens — email may not be parseable.
        // Fall back to subscription type label so the flow can always advance.
        let email = ClaudeCodeManager.parseEmail(from: data)
            ?? ClaudeCodeManager.parseDisplayLabel(from: data)
            ?? "Claude Code"
        pendingProfileEmail = email
        cancelLoginTimeout()
        addingStep = .confirmProfile
    }

    private func cancelLoginTimeout() {
        loginTimeout?.cancel()
        loginTimeout = nil
    }

    private func loginTimedOut() {
        guard addingStep == .waitingLogin else { return }
        cancelLoginTimeout()
        addingStep = .idle
        isAddingAccount = false
        stopAuthWatcher()
    }

    func confirmPendingProfile(alias: String) {
        guard let newProfile = profileManager.captureCurrentAuth(alias: alias, provider: pendingProvider) else {
            cancelAddAccount()
            return
        }
        var config = profileManager.loadConfig()
        var profile = newProfile
        let shouldActivate = config.activeProfileId == nil
        if shouldActivate { profile.activatedAt = Date() }
        config.profiles.append(profile)
        if shouldActivate {
            config.activeProfileId = profile.id
            try? profileManager.activate(profile: profile)
            activeProfile = profile
        }
        profileManager.saveConfig(config)
        profiles = config.profiles
        addingStep = .done
        isAddingAccount = false
        stopAuthWatcher()
        closeAddAccountWindow()
        notifyProfileChanged()
        sendNotification(title: "Hesap eklendi", body: profile.displayName)
        Task { await fetchAllRateLimits() }
    }

    func cancelAddAccount() {
        cancelLoginTimeout()
        claudeAuthPoller?.invalidate()
        claudeAuthPoller = nil
        isAddingAccount = false
        addingStep = .idle
        pendingProfileEmail = ""
        aliasText = ""
        stopAuthWatcher()
        closeAddAccountWindow()
        if let a = activeProfile { try? profileManager.activate(profile: a) }
    }

    // MARK: - Statistics Reset

    func resetStatistics() {
        let alert = NSAlert()
        alert.messageText = L("İstatistikleri sıfırla?", "Reset statistics?")
        alert.informativeText = L(
            "Tüm token ve maliyet geçmişi silinecek. Bu işlem geri alınamaz.",
            "All token and cost history will be deleted. This cannot be undone.")
        alert.addButton(withTitle: L("Sıfırla", "Reset"))
        alert.addButton(withTitle: L("İptal", "Cancel"))
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-switcher/cache")
        let filesToDelete = [
            "event-deltas-v2.json",
            "token-usage.json.mod",
            "session-meta-v2.json",
            "session-meta-v2.mod"
        ]
        for name in filesToDelete {
            try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent(name))
        }

        tokenUsage     = [:]
        dailyUsage     = [:]
        costs          = [:]
        forecasts      = [:]
        projectUsage   = []
        sessionSummaries = []
        hourlyActivity = []
        expensiveTurns = []
        paceHistory    = []
        warned80PercentIds = []

        refreshTokenUsage()
    }

    // MARK: - Re-login for Stale Accounts

    func beginRelogin(for profile: Profile) {
        reloginTargetId = profile.id
        openTerminalWithCodexLogin()
        watchAuthFileForRelogin()
    }

    private func watchAuthFileForRelogin() {
        stopAuthWatcher()
        let fd = open(ProfileManager.codexAuthPath.path, O_EVTONLY)
        guard fd >= 0 else { return }
        authWatcherFd = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in self?.reloginAuthChanged() }
        src.setCancelHandler { [weak self] in
            if let self, self.authWatcherFd >= 0 { close(self.authWatcherFd); self.authWatcherFd = -1 }
        }
        src.resume()
        authWatcher = src
    }

    private func reloginAuthChanged() {
        guard let targetId = reloginTargetId else { return }
        if let last = lastAuthWriteDate, Date().timeIntervalSince(last) < 0.5 { return }
        lastAuthWriteDate = Date()

        guard let data = try? Data(contentsOf: ProfileManager.codexAuthPath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = dict["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String,
              let newAccountId = profileManager.extractAccountId(from: accessToken) else { return }

        reloginTargetId = nil
        stopAuthWatcher()

        guard let profile = profiles.first(where: { $0.id == targetId }) else { return }

        if profile.accountId == newAccountId {
            try? data.write(to: profileManager.authPath(for: profile), options: .atomic)
            staleProfileIds.remove(targetId)
            sendNotification(
                title: L("Giriş yenilendi", "Re-login successful"),
                body: profile.displayName
            )
            Task { await fetchAllRateLimits() }
        } else {
            sendNotification(
                title: L("Hatalı hesap", "Wrong account"),
                body: L("Farklı bir hesaba giriş yapıldı. Tekrar deneyin.", "A different account was detected. Please try again.")
            )
        }
    }

    func delete(profile: Profile) {
        profileManager.deleteProfile(profile)
        rateLimits.removeValue(forKey: profile.id)
        var config = profileManager.loadConfig()
        config.profiles.removeAll { $0.id == profile.id }
        if config.activeProfileId == profile.id {
            config.activeProfileId = config.profiles.first?.id
            if let next = config.profiles.first {
                try? profileManager.activate(profile: next)
                activeProfile = next
            } else { activeProfile = nil }
        }
        profileManager.saveConfig(config)
        profiles = config.profiles
        notifyProfileChanged()
    }

    // MARK: - Auth Watcher

    private func watchAuthFileForNewLogin() {
        stopAuthWatcher()
        let fd = open(ProfileManager.codexAuthPath.path, O_EVTONLY)
        guard fd >= 0 else { return }
        authWatcherFd = fd
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in self?.authFileChanged() }
        src.setCancelHandler { [weak self] in
            if let self, self.authWatcherFd >= 0 { close(self.authWatcherFd); self.authWatcherFd = -1 }
        }
        src.resume()
        authWatcher = src
    }

    private func authFileChanged() {
        // Debounce: ignore events within 500ms of our own write or last external event
        if let last = lastAuthWriteDate, Date().timeIntervalSince(last) < 0.5 { return }
        lastAuthWriteDate = Date() // reset for rapid external events too

        if isAddingAccount {
            // Existing add-account flow
            guard let data = try? Data(contentsOf: ProfileManager.codexAuthPath),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tokens = dict["tokens"] as? [String: Any],
                  let access = tokens["access_token"] as? String else { return }
            pendingProfileEmail = profileManager.extractEmail(from: access) ?? "bilinmeyen"
            addingStep = .confirmProfile
        } else {
            // External modification detected — verify
            Task {
                let result = profileManager.verifyAndRecoverActiveAuth()
                if result == .unrecoverable {
                    sendNotification(
                        title: L("Auth sorunu", "Auth issue"),
                        body: L("Auth dosyası bozuldu. Hesapları yeniden giriş yapmanız gerekebilir.", "Auth file corrupted. You may need to re-login to your accounts.")
                    )
                }
            }
        }
    }

    private func stopAuthWatcher() { authWatcher?.cancel(); authWatcher = nil }

    // MARK: - Helpers

    private func openTerminalWithCodexLogin() {
        // codex login opens a browser and writes auth.json — no terminal needed
        let codexPath = findCLIPath("codex")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: codexPath)
        task.arguments = ["login"]
        task.standardInput = nil
        task.standardOutput = nil
        task.standardError = nil
        try? task.run()
    }

    private func notifyProfileChanged() {
        NotificationCenter.default.post(name: .profileChanged, object: nil)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
