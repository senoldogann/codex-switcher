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
    @Published var lastKnownLimitState: [UUID: Bool] = [:]  // track for restored notifications
    @Published var isSessionActive: Bool = false  // live session indicator

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
    private var lastAuthWriteDate: Date?
    private var consecutiveFetchFailures: Int = 0
    private var paceHistory: [SessionPacePoint] = []

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
            self?.refreshTokenUsage()
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
        // İlk fetch popover açılınca yapılır; sonra her 5 dakikada sessizce güncelle
        rateLimitTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.fetchAllRateLimits(showSpinner: false) }
        }
    }

    // MARK: - Rate Limit Fetch (tüm hesaplar için)

    func fetchAllRateLimits(showSpinner: Bool = true) async {
        if showSpinner { isFetchingLimits = true }
        defer { if showSpinner { isFetchingLimits = false } }

        let fetcher = self.fetcher

        let credPairs: [(UUID, AuthCredentials)] = profiles.compactMap { profile in
            guard let dict = profileManager.readAuthDict(for: profile),
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
                // Restored notification
                if lastKnownLimitState[id] == true, info.limitReached == false {
                    sendNotification(
                        title: L("Limit sıfırlandı", "Limit reset"),
                        body: L("\(profiles.first(where: { $0.id == id })?.displayName ?? "Hesap") kullanıma hazır", "Account is ready to use again")
                    )
                }
                lastKnownLimitState[id] = info.limitReached
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
        updateCostsAndForecasts()
    }

    func refreshTokenUsage() {
        let profiles = self.profiles
        let history  = self.switchHistory
        let parser   = self.tokenParser
        DispatchQueue.global(qos: .utility).async {
            let result = parser.calculate(profiles: profiles, history: history)
            DispatchQueue.main.async {
                self.tokenUsage = result
                self.updateCostsAndForecasts()
            }
        }
    }

    private func updateCostsAndForecasts() {
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

        // Update pace history
        let totalTokens = tokenUsage.values.reduce(0) { $0 + $1.totalTokens }
        if totalTokens > 0 {
            paceHistory.append(SessionPacePoint(timestamp: Date(), cumulativeTokens: totalTokens))
            // Keep last 24 hours of data points
            let cutoff = Date().addingTimeInterval(-24 * 3600)
            paceHistory.removeAll { $0.timestamp < cutoff }
        }
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
        activeProfile = config.profiles.first { $0.id == candidate.id }
        profiles = config.profiles
        allExhausted = false
        activeTurns = 0
        notifyProfileChanged()
        sendNotification(title: L("Hesap değiştirildi", "Account switched"), body: "\(candidate.displayName) — \(reason)")
        Task { await fetchAllRateLimits() }
        restartCodexIfRunning()
    }

    // MARK: - Codex Restart

    private func restartCodexIfRunning() {
        // Codex'i otomatik restart ETME — aktif stream'i koparır
        // "stream disconnected before completion" hatasına sebep olur.
        // Sadece kullanıcıya bildirim gönder, bir sonraki istekte yeni auth kullanılır.
        let codexRunning = NSWorkspace.shared.runningApplications.contains {
            $0.localizedName == "Codex" && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        guard codexRunning else { return }
        sendNotification(
            title: L("Codex'i yeniden başlat", "Restart Codex"),
            body: L("Hesap değiştirildi. Yeni hesabı kullanmak için Codex'i kapatıp açın.", "Account switched. Quit and reopen Codex to use the new account.")
        )
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
        if let url = Bundle.module.url(forResource: "codex", withExtension: "icns"),
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
        guard !allExhausted else { return }
        // Cooldown: son otomatik geçişten bu yana yeterli süre geçmedi mi?
        if let last = lastAutoSwitchDate,
           Date().timeIntervalSince(last) < Self.switchCooldown { return }
        lastAutoSwitchDate = Date()
        switchToNext(reason: L("Limit doldu", "Limit reached"))
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

    func beginAddAccount() {
        isAddingAccount = true
        addingStep = .waitingLogin
        openTerminalWithCodexLogin()
        watchAuthFileForNewLogin()

        // 120 saniye timeout — login tamamlanmazsa otomatik iptal
        cancelLoginTimeout()
        let timeout = DispatchWorkItem { [weak self] in
            self?.loginTimedOut()
        }
        loginTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: timeout)
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
        guard let newProfile = profileManager.captureCurrentAuth(alias: alias) else {
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
        isAddingAccount = false
        addingStep = .idle
        pendingProfileEmail = ""
        aliasText = ""
        stopAuthWatcher()
        closeAddAccountWindow()
        if let a = activeProfile { try? profileManager.activate(profile: a) }
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
        // codex login'i arka planda calistir — Terminal acilmaz
        // codex login kendi browser'ini acar ve auth.json'u yazar
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["codex", "login"]
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
