# Reliability Pack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add account health checks, auth recovery, switch verification, and exhaustion UX to CodexSwitcher.

**Architecture:** Extend existing `RateLimitFetcher` with `FetchResult` enum for health status, add verification/rollback to `ProfileManager.activate()`, integrate boot-time auth recovery into `AppStore.init()`, and add exhaustion banner + health indicators to `MenuContentView`.

**Tech Stack:** Swift 6.2, SwiftUI, Foundation, AppKit, macOS 26+

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/CodexSwitcher/RateLimitFetcher.swift` | Modify | Change `fetch()` return type from `RateLimitInfo?` to `FetchResult` enum |
| `Sources/CodexSwitcher/ProfileManager.swift` | Modify | Add `verifyAndRecoverActiveAuth()`, `verifyActiveAccount()`, backup/rollback in `activate()`, cleanup stale backup on boot |
| `Sources/CodexSwitcher/AppStore.swift` | Modify | Call recovery before `loadProfiles()`, integrate verification into `activateCandidate()`, add `staleProfileIds`, extend `authFileChanged()` with debounce, add `lastAuthWriteDate` |
| `Sources/CodexSwitcher/MenuContentView.swift` | Modify | Add health indicator dots, exhaustion banner, lock icons, override button |
| `Sources/CodexSwitcher/L10n.swift` | Modify | Add TR/EN strings for new UI elements |
| `Sources/CodexSwitcher/Models.swift` | No change | Existing types sufficient |

---

### Task 1: FetchResult enum — RateLimitFetcher return type

**Files:**
- Modify: `Sources/CodexSwitcher/RateLimitFetcher.swift:63-77`

- [ ] **Step 1: Add FetchResult enum above RateLimitFetcher class**

Add this enum after the `RateLimitInfo` struct (line 47), before `RateLimitFetcher` class:

```swift
enum FetchResult {
    case success(RateLimitInfo)
    case stale
    case failure
}
```

- [ ] **Step 2: Change `fetch()` return type and implementation**

Replace the `fetch` method (lines 63-77):

```swift
func fetch(credentials: AuthCredentials) async -> FetchResult {
    var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
    req.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
    req.setValue(credentials.accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
    req.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
    req.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response): (Data, URLResponse)
    do {
        (data, response) = try await session.data(for: req)
    } catch {
        return .failure
    }

    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

    switch statusCode {
    case 200:
        guard let info = parse(data) else { return .failure }
        return .success(info)
    case 401, 403:
        return .stale
    default:
        return .failure
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `bash build.sh`
Expected: Build succeeds (caller in AppStore will have compile error — that's expected, fix in Task 2)

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexSwitcher/RateLimitFetcher.swift
git commit -m "feat: change RateLimitFetcher.fetch() to return FetchResult enum"
```

---

### Task 2: Update AppStore.fetchAllRateLimits() for FetchResult

**Files:**
- Modify: `Sources/CodexSwitcher/AppStore.swift:72-99`
- Modify: `Sources/CodexSwitcher/AppStore.swift:11-22` (add `staleProfileIds`)

- [ ] **Step 1: Add `staleProfileIds` state property**

Add after line 22 (`@Published var tokenUsage`):

```swift
@Published var staleProfileIds: Set<UUID> = []
```

- [ ] **Step 2: Update `fetchAllRateLimits()` to handle FetchResult**

Replace the entire `fetchAllRateLimits` method (lines 72-99):

```swift
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
    for (id, result) in results {
        switch result {
        case .success(let info):
            rateLimits[id] = info
        case .stale:
            newStale.insert(id)
        case .failure:
            break // keep existing rateLimits entry if any
        }
    }
    staleProfileIds = newStale
    NotificationCenter.default.post(name: .rateLimitsUpdated, object: nil)
    refreshTokenUsage()
}
```

- [ ] **Step 3: Build and verify**

Run: `bash build.sh`
Expected: Build succeeds, no warnings

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexSwitcher/AppStore.swift
git commit -m "feat: update AppStore to handle FetchResult, add staleProfileIds"
```

---

### Task 3: Auth Recovery — verifyAndRecoverActiveAuth in ProfileManager

**Files:**
- Modify: `Sources/CodexSwitcher/ProfileManager.swift` (add new methods after `bootstrap()`)

- [ ] **Step 1: Add AuthVerificationResult enum**

Add after `SwitcherError` enum (line 158):

```swift
enum AuthVerificationResult {
    case valid
    case recovered
    case unrecoverable
}
```

- [ ] **Step 2: Add `verifyAndRecoverActiveAuth()` method**

Add after `bootstrap()` method (line 32):

```swift
/// Verify auth.json on boot and recover if broken. Must run BEFORE loadProfiles().
func verifyAndRecoverActiveAuth() -> AuthVerificationResult {
    // Clean up stale backup from previous crash
    if FileManager.default.fileExists(atPath: Self.authBackupPath.path) {
        try? FileManager.default.removeItem(at: Self.authBackupPath)
    }

    let config = loadConfig()
    guard let activeId = config.activeProfileId,
          let activeProfile = config.profiles.first(where: { $0.id == activeId }) else {
        return .valid // no active profile, nothing to verify
    }

    // Check if current auth.json is valid
    if isValidAuthFile(at: Self.codexAuthPath, expectedAccountId: activeProfile.accountId) {
        return .valid
    }

    // Try to recover from profile's stored auth
    let profileAuthPath = authPath(for: activeProfile)
    if FileManager.default.fileExists(atPath: profileAuthPath.path),
       let data = try? Data(contentsOf: profileAuthPath),
       isValidAuthData(data) {
        try? data.write(to: Self.codexAuthPath, options: .atomic)
        return .recovered
    }

    return .unrecoverable
}

private func isValidAuthFile(at url: URL, expectedAccountId: String) -> Bool {
    guard let data = try? Data(contentsOf: url),
          isValidAuthData(data) else { return false }
    guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tokens = dict["tokens"] as? [String: Any],
          let accessToken = tokens["access_token"] as? String else { return false }
    let actualId = extractAccountId(from: accessToken)
    return actualId == expectedAccountId
}

private func isValidAuthData(_ data: Data) -> Bool {
    guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tokens = dict["tokens"] as? [String: Any],
          tokens["access_token"] as? String != nil else { return false }
    return true
}
```

- [ ] **Step 3: Build and verify**

Run: `bash build.sh`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexSwitcher/ProfileManager.swift
git commit -m "feat: add verifyAndRecoverActiveAuth for boot-time auth recovery"
```

---

### Task 4: Switch Verification — verifyActiveAccount + backup/rollback

**Files:**
- Modify: `Sources/CodexSwitcher/ProfileManager.swift` (add after Task 3 additions)

- [ ] **Step 1: Add authBackupPath constant**

Add after `codexAuthPath` property (line 24):

```swift
static let authBackupPath: URL = {
    switcherDir.appendingPathComponent("auth-backup.json")
}()
```

- [ ] **Step 2: Add VerifyResult and VerifyError enums**

Add after `AuthVerificationResult` enum:

```swift
enum VerifyResult: Equatable {
    case verified
    case failed(VerifyError)
}

enum VerifyError: Equatable {
    case fileMissing
    case invalidJSON
    case jwtParseFailed
    case claimNotFound
    case mismatch(expected: String, actual: String)
}
```

- [ ] **Step 3: Add `verifyActiveAccount()` method**

Add after the `verifyAndRecoverActiveAuth()` helper methods:

```swift
/// Verify that the current auth.json matches the expected account.
func verifyActiveAccount(expectedAccountId: String) -> VerifyResult {
    guard FileManager.default.fileExists(atPath: Self.codexAuthPath.path) else {
        return .failed(.fileMissing)
    }
    guard let data = try? Data(contentsOf: Self.codexAuthPath),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tokens = dict["tokens"] as? [String: Any],
          let accessToken = tokens["access_token"] as? String else {
        return .failed(.invalidJSON)
    }
    guard let actualId = extractAccountId(from: accessToken) else {
        return .failed(.jwtParseFailed)
    }
    guard !actualId.isEmpty else {
        return .failed(.claimNotFound)
    }
    guard actualId == expectedAccountId else {
        return .failed(.mismatch(expected: expectedAccountId, actual: actualId))
    }
    return .verified
}
```

- [ ] **Step 4: Replace `activate()` with backup/rollback version**

Replace the `activate(profile:)` method (lines 89-102):

```swift
/// Profili aktif et — backup oluştur, atomik olarak değiştir, doğrula.
/// Doğrulama başarısızsa backup'tan geri döner.
@discardableResult
func activate(profile: Profile) throws -> VerifyResult {
    let src = authPath(for: profile)
    guard FileManager.default.fileExists(atPath: src.path) else {
        throw SwitcherError.missingAuthFile(profile.email)
    }

    let newData = try Data(contentsOf: src)

    // Backup current auth.json
    if FileManager.default.fileExists(atPath: Self.codexAuthPath.path) {
        try? FileManager.default.copyItem(
            at: Self.codexAuthPath,
            to: Self.authBackupPath
        )
    }

    // Atomic write
    let tmp = Self.codexAuthPath.deletingLastPathComponent()
        .appendingPathComponent(".auth_tmp_\(UUID().uuidString).json")
    try newData.write(to: tmp, options: .atomic)
    guard FileManager.default.replaceItemAt(Self.codexAuthPath, withItemAt: tmp) != nil else {
        throw SwitcherError.activationFailed(profile.email)
    }

    // Verify
    let verifyResult = verifyActiveAccount(expectedAccountId: profile.accountId)
    if case .failed = verifyResult {
        // Rollback from backup
        if FileManager.default.fileExists(atPath: Self.authBackupPath.path) {
            try? FileManager.default.replaceItemAt(
                Self.codexAuthPath,
                withItemAt: Self.authBackupPath
            )
        }
    } else {
        // Success — clean up backup
        try? FileManager.default.removeItem(at: Self.authBackupPath)
    }

    return verifyResult
}
```

- [ ] **Step 5: Add `activationFailed` to SwitcherError**

Add to the `SwitcherError` enum (after `allProfilesExhausted`):

```swift
case activationFailed(String)
```

And add its case to `errorDescription`:

```swift
case .activationFailed(let email):
    return "Aktivasyon başarısız: \(email)"
```

- [ ] **Step 6: Build and verify**

Run: `bash build.sh`
Expected: Build may have warnings about unused return value — that's fine, caller will use it in Task 5

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexSwitcher/ProfileManager.swift
git commit -m "feat: add verifyActiveAccount, backup/rollback to activate()"
```

---

### Task 5: Integrate verification into AppStore.activateCandidate()

**Files:**
- Modify: `Sources/CodexSwitcher/AppStore.swift:209-242` (activateCandidate method)
- Modify: `Sources/CodexSwitcher/AppStore.swift:43-59` (init — add recovery call)
- Modify: `Sources/CodexSwitcher/AppStore.swift` (add `lastAuthWriteDate` + debounce)

- [ ] **Step 1: Add `lastAuthWriteDate` property**

Add after `lastAutoSwitchDate` (line 37):

```swift
private var lastAuthWriteDate: Date?
```

- [ ] **Step 2: Add recovery call to init()**

In `init()` (line 44), replace `profileManager.bootstrap()` with:

```swift
profileManager.bootstrap()
let recoveryResult = profileManager.verifyAndRecoverActiveAuth()
if recoveryResult == .unrecoverable {
    // All profiles will show as stale; user needs to re-login
}
```

- [ ] **Step 3: Update `activateCandidate()` to use verification result**

Replace the `activateCandidate` method (lines 209-242):

```swift
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
```

- [ ] **Step 4: Extend authFileChanged() with debounce**

Replace `authFileChanged()` method (lines 448-455):

```swift
private func authFileChanged() {
    // Debounce: ignore events within 500ms of our own write
    if let last = lastAuthWriteDate, Date().timeIntervalSince(last) < 0.5 { return }

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
```

- [ ] **Step 5: Build and verify**

Run: `bash build.sh`
Expected: Build succeeds, no warnings

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexSwitcher/AppStore.swift
git commit -m "feat: integrate verification + recovery into AppStore"
```

---

### Task 6: Health indicators in MenuContentView

**Files:**
- Modify: `Sources/CodexSwitcher/MenuContentView.swift:70-150` (profileRow method)

- [ ] **Step 1: Add health indicator dot to profileRow**

In the `profileRow` method, after the `codexAvatar` line (line 78), add health indicator. Find this section:

```swift
HStack(alignment: .center, spacing: 12) {
    codexAvatar(size: 36, active: isActive)
```

Change to:

```swift
HStack(alignment: .center, spacing: 12) {
    codexAvatar(size: 36, active: isActive)
    healthDot(for: profile)
```

- [ ] **Step 2: Add `healthDot` helper method**

Add after the `separator` property (after line 66):

```swift
private func healthDot(for profile: Profile) -> some View {
    let color: Color = {
        if store.staleProfileIds.contains(profile.id) {
            return .yellow
        }
        if store.rateLimits[profile.id] != nil {
            return .green
        }
        return .gray
    }()

    return Circle()
        .fill(color)
        .frame(width: 6, height: 6)
}
```

Note: Exhausted profiles (limitReached) show a lock icon (Task 7B), not a red dot. The health dot reflects auth health only.

- [ ] **Step 3: Build and verify**

Run: `bash build.sh`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexSwitcher/MenuContentView.swift
git commit -m "feat: add health indicator dots to profile rows"
```

---

### Task 7A: Exhaustion banner + nextResetInfo

**Files:**
- Modify: `Sources/CodexSwitcher/AppStore.swift` (add `nextResetInfo`)
- Modify: `Sources/CodexSwitcher/MenuContentView.swift` (add `mainContent` restructure + `exhaustionBanner`)

- [ ] **Step 1: Add `nextResetInfo` to AppStore**

Add after `rateLimit(for:)` method:

```swift
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
```

- [ ] **Step 2: Replace `mainContent` with full version including exhaustion banner**

Replace the existing `mainContent` computed property (the `if store.profiles.isEmpty { emptyState } else { ScrollView... }` block in the body):

```swift
private var mainContent: some View {
    Group {
        if store.allExhausted && !store.profiles.isEmpty {
            exhaustionBanner
        }
        if store.profiles.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(store.profiles.enumerated()), id: \.element.id) { i, p in
                        if i > 0 { separator }
                        profileRow(p)
                    }
                }
            }
            .frame(maxHeight: store.allExhausted ? 360 : 420)
        }
    }
}
```

- [ ] **Step 3: Add `exhaustionBanner` property**

Add after the `mainContent` property:

```swift
private var exhaustionBanner: some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(Str.allExhausted)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(gw.opacity(0.8))
            Spacer()
        }

        if let info = store.nextResetInfo {
            Text(L("İlk sıfırlanacak: \(info.profileName) — \(info.resetTime)",
                   "First reset: \(info.profileName) at \(info.resetTime)"))
                .font(.system(size: 10))
                .foregroundStyle(gw.opacity(0.45))
        }

        Button {
            store.switchToNext(reason: L("Manuel override", "Manual override"))
        } label: {
            Text(Str.switchAnyway)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(gw.opacity(0.6))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(gw.opacity(0.03))
}
```

- [ ] **Step 4: Build and verify**

Run: `bash build.sh`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexSwitcher/AppStore.swift Sources/CodexSwitcher/MenuContentView.swift
git commit -m "feat: add exhaustion banner with next reset info"
```

---

### Task 7B: Lock icons on exhausted profiles

**Files:**
- Modify: `Sources/CodexSwitcher/MenuContentView.swift` (profileRow — add lock icon)

- [ ] **Step 1: Add lock icon to exhausted profiles**

In `profileRow`, in the name row HStack (after the green dot for active), add lock icon for exhausted profiles. Find this section around line 88-94:

```swift
if isActive {
    Circle()
        .fill(Color.green)
        .frame(width: 5, height: 5)
        .shadow(color: .green, radius: 4)
}
```

After the closing brace of the `if isActive` block, add:

```swift
if let rl = store.rateLimit(for: profile), rl.limitReached {
    Image(systemName: "lock.fill")
        .font(.system(size: 8))
        .foregroundStyle(.red.opacity(0.6))
}
```

- [ ] **Step 2: Build and verify**

Run: `bash build.sh`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/CodexSwitcher/MenuContentView.swift
git commit -m "feat: add lock icons to exhausted profile rows"
```

---

### Task 7C: Localization strings + override button

**Files:**
- Modify: `Sources/CodexSwitcher/L10n.swift` (add strings)

- [ ] **Step 1: Add localization strings to L10n.swift**

Add after the existing strings (before the closing brace of `Str`):

```swift
static var switchAnyway: String { L("Yine de geç",        "Switch anyway") }
```

- [ ] **Step 2: Build and verify**

Run: `bash build.sh`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/CodexSwitcher/L10n.swift
git commit -m "feat: add localization strings for exhaustion UX"
```

---

### Task 8: Final verification and cleanup

**Files:**
- All modified files

- [ ] **Step 1: Full build**

Run: `bash build.sh`
Expected: Build succeeds, no warnings

- [ ] **Step 2: Verify all features are wired up**

Checklist:
- [ ] `FetchResult` enum in RateLimitFetcher — handles 200/401/403/network
- [ ] `staleProfileIds` updated in `fetchAllRateLimits()`
- [ ] `verifyAndRecoverActiveAuth()` called before `loadProfiles()` in init
- [ ] `activate()` creates backup, verifies, rolls back on failure
- [ ] `activateCandidate()` handles `.failed` with one retry
- [ ] `authFileChanged()` has 500ms debounce, distinguishes add-account vs external modification
- [ ] Health dots in profile rows (green/yellow/gray — no red, exhaustion uses lock icon)
- [ ] Exhaustion banner shown when `allExhausted == true && !profiles.isEmpty`
- [ ] Lock icon on exhausted profiles
- [ ] "Switch anyway" button calls `switchToNext(reason: "Manuel override")`
- [ ] `nextResetInfo` uses `isDateInToday` for date formatting
- [ ] `authBackupPath` cleaned up on boot

- [ ] **Step 3: Commit final state**

```bash
git status
git log --oneline -5
```

- [ ] **Step 4: Restart app for manual testing**

```bash
killall CodexSwitcher 2>/dev/null; sleep 1; open CodexSwitcher.app
```
