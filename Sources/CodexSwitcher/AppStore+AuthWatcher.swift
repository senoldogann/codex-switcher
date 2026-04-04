import Foundation

// MARK: - Auth File Watching

extension AppStore {

    func watchAuthFileForNewLogin() {
        stopAuthWatcher()
        let fd = open(ProfileManager.codexAuthPath.path, O_EVTONLY)
        guard fd >= 0 else { return }
        authWatcherFd = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in self?.authFileChanged() }
        src.setCancelHandler { [weak self] in
            if let self, self.authWatcherFd >= 0 { close(self.authWatcherFd); self.authWatcherFd = -1 }
        }
        src.resume()
        authWatcher = src
    }

    private func authFileChanged() {
        if let last = lastAuthWriteDate, Date().timeIntervalSince(last) < 0.5 { return }
        lastAuthWriteDate = Date()

        if isAddingAccount {
            guard let data = try? Data(contentsOf: ProfileManager.codexAuthPath),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tokens = dict["tokens"] as? [String: Any],
                  let access = tokens["access_token"] as? String else { return }
            pendingProfileEmail = profileManager.extractEmail(from: access) ?? "bilinmeyen"
            addingStep = .confirmProfile
        } else {
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

    func watchAuthFileForRelogin() {
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

    func stopAuthWatcher() {
        authWatcher?.cancel()
        authWatcher = nil
    }
}
