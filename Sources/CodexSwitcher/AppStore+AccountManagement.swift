import Foundation
import AppKit
import SwiftUI

// MARK: - Account Management (Add / Rename / Delete / Reset)

extension AppStore {

    // MARK: Add Account Window

    func openAddAccountWindow() {
        addingStep = .idle
        isAddingAccount = false
        addAccountErrorMessage = nil
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

    func dismissAddAccountFlow(closeWindow: Bool = false) {
        cancelLoginTimeout()
        stopCodexLoginProcess(suppressFailureFeedback: true)
        isAddingAccount = false
        addingStep = .idle
        addAccountErrorMessage = nil
        pendingProfileEmail = ""
        aliasText = ""
        stopAuthWatcher()
        if closeWindow { closeAddAccountWindow() }
    }

    // MARK: Add Account Flow

    func beginAddAccount() {
        addAccountErrorMessage = nil
        isAddingAccount = true
        addingStep = .waitingLogin

        watchAuthFileForNewLogin()
        guard startCodexLogin() else {
            stopAuthWatcher()
            return
        }

        cancelLoginTimeout()
        let timeout = DispatchWorkItem { [weak self] in self?.loginTimedOut() }
        loginTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: timeout)
    }

    func confirmPendingProfile(alias: String) {
        guard let newProfile = profileManager.captureCurrentAuth(alias: alias) else {
            cancelAddAccount()
            return
        }
        stopCodexLoginProcess(suppressFailureFeedback: true)
        var config = profileManager.loadConfig()
        var profile = newProfile
        let shouldActivate = config.activeProfileId == nil
        if shouldActivate { profile.activatedAt = Date() }
        config.profiles.append(profile)
        if shouldActivate {
            config.activeProfileId = profile.id
            _ = try? profileManager.activate(profile: profile)
            activeProfile = profile
        }
        profileManager.saveConfig(config)
        profiles = config.profiles
        addingStep = .done
        isAddingAccount = false
        addAccountErrorMessage = nil
        stopAuthWatcher()
        closeAddAccountWindow()
        notifyProfileChanged()
        sendNotification(title: "Hesap eklendi", body: profile.displayName)
        Task { await fetchAllRateLimits() }
    }

    func cancelAddAccount() {
        cancelLoginTimeout()
        stopCodexLoginProcess(suppressFailureFeedback: true)
        isAddingAccount = false
        addingStep = .idle
        addAccountErrorMessage = nil
        pendingProfileEmail = ""
        aliasText = ""
        stopAuthWatcher()
        closeAddAccountWindow()
        if let a = activeProfile { _ = try? profileManager.activate(profile: a) }
    }

    // MARK: Rename

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

    func moveProfile(_ draggedProfileId: UUID, to destinationIndex: Int) {
        var config = profileManager.loadConfig()
        guard let sourceIndex = config.profiles.firstIndex(where: { $0.id == draggedProfileId }) else { return }

        let boundedDestination = max(0, min(destinationIndex, config.profiles.count))
        let profile = config.profiles.remove(at: sourceIndex)
        let adjustedDestination = sourceIndex < boundedDestination ? boundedDestination - 1 : boundedDestination

        guard adjustedDestination != sourceIndex else {
            config.profiles.insert(profile, at: sourceIndex)
            return
        }

        config.profiles.insert(profile, at: adjustedDestination)
        config.roundRobinIndex = min(config.roundRobinIndex, max(config.profiles.count - 1, 0))

        profileManager.saveConfig(config)
        profiles = config.profiles
        if let activeProfileId = config.activeProfileId {
            activeProfile = config.profiles.first(where: { $0.id == activeProfileId })
        }
        notifyProfileChanged()
    }

    func showRenameDialog(for profile: Profile) {
        let alert = NSAlert()
        alert.messageText = Str.renameTitle
        alert.informativeText = profile.email
        alert.addButton(withTitle: Str.save)
        alert.addButton(withTitle: Str.cancel)

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

    // MARK: Delete

    func delete(profile: Profile) {
        profileManager.deleteProfile(profile)
        rateLimits.removeValue(forKey: profile.id)
        var config = profileManager.loadConfig()
        config.profiles.removeAll { $0.id == profile.id }
        if config.activeProfileId == profile.id {
            config.activeProfileId = config.profiles.first?.id
            if let next = config.profiles.first {
                _ = try? profileManager.activate(profile: next)
                activeProfile = next
            } else { activeProfile = nil }
        }
        profileManager.saveConfig(config)
        profiles = config.profiles
        notifyProfileChanged()
    }

    // MARK: Statistics Reset

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
            "session-meta-v3.json",
            "session-meta-v3.mod"
        ]
        for name in filesToDelete {
            try? FileManager.default.removeItem(at: cacheDir.appendingPathComponent(name))
        }

        tokenUsage         = [:]
        costs              = [:]
        forecasts          = [:]
        analyticsSnapshot  = .empty(for: analyticsTimeRange)
        paceHistory        = []
        rateLimitAuditSamples = [:]
        warned80PercentIds = []

        refreshTokenUsage()
    }

    // MARK: Re-login

    func beginRelogin(for profile: Profile) {
        reloginTargetId = profile.id
        watchAuthFileForRelogin()
        guard startCodexLogin() else {
            reloginTargetId = nil
            stopAuthWatcher()
            return
        }
    }
}
