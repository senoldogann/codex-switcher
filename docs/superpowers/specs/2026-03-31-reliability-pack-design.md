# Reliability Pack — Design Spec

**Date:** 2026-03-31
**Status:** Draft (rev1 — post-review fixes)
**Author:** CodexSwitcher Team

## Overview

Four reliability improvements to CodexSwitcher that make account switching safer, more observable, and more resilient to failure:

1. **Account Health Checks** — Per-account health indicators (healthy/stale/unknown)
2. **Auth Recovery** — Automatic rollback and recovery when auth.json is corrupted
3. **Switch Verification** — Post-switch confirmation that Codex is using the correct account
4. **Exhaustion UX** — Clear visual feedback when all accounts are rate-limited

## Architecture

### 1. Account Health Checks

#### Problem
No visibility into whether an account's auth token is valid, whether the API is responding, or whether the account can actually be used.

#### Solution

Add a `HealthStatus` enum and compute it during rate limit polling:

```swift
enum HealthStatus: Equatable {
    case healthy          // API 200, auth valid, not rate-limited
    case stale            // API 401/403, token expired (re-login needed)
    case unknown          // Network error or no fetch yet
}
```

**Note:** `.exhausted` is NOT a HealthStatus. Exhaustion is derived from `rateLimits[id]?.limitReached == true` — this avoids a third source of truth (fixes H2).

**Data flow:**
- `RateLimitFetcher.fetch()` return type changes from `RateLimitInfo?` to `FetchResult` (fixes H1, C1):

```swift
enum FetchResult {
    case success(RateLimitInfo)   // HTTP 200
    case stale                    // HTTP 401/403 — token expired
    case failure                  // Network error, timeout, non-auth 4xx/5xx
}
```

- `RateLimitFetcher.fetch()` now captures the HTTP status code before returning nil. On 401/403 → `.stale`. On network error → `.failure`. On 200 → `.success(RateLimitInfo)`.
- `AppStore.fetchAllRateLimits()` maps `FetchResult` → updates `rateLimits` dict AND derives health status on the fly.

**Health is a computed property, not stored state** (fixes M2):
```swift
func healthStatus(for profile: Profile) -> HealthStatus {
    guard let rl = rateLimits[profile.id] else { return .unknown }
    if rl.limitReached { return .healthy } // exhausted but healthy auth — shown via lock icon
    return .healthy
}
// Actually: health is derived inline in the UI from rateLimits + fetch result.
// No separate healthStatuses dictionary needed.
```

**Simplified approach:** Instead of a separate `HealthStatus` type, the UI directly reads from `RateLimitInfo`:
- `rateLimits[id] == nil` → gray dot (never checked)
- `rateLimits[id]?.limitReached == true` → red lock (exhausted)
- `fetchResult was .stale` → yellow dot (stale token)
- `fetchResult was .failure` → gray dot (unknown)
- `fetchResult was .success` → green dot (healthy)

To support this, `fetchAllRateLimits` tracks stale profiles in a `Set<UUID>`:
```swift
@Published var staleProfileIds: Set<UUID> = []
```

**UI changes:**
- Each profile row shows a small `Circle().fill(color)` indicator using SF Symbols colors (fixes L1):
  - `.green` = healthy (API 200, not exhausted)
  - `.yellow` = stale (401/403, re-login needed)
  - `.red` = exhausted (limitReached = true)
  - `.gray` = unknown (not yet checked or network error)
- Health check runs on popover open (with rate limit fetch) and via existing 60-second timer (fixes M1 — keep existing interval, don't change to 5 min)

**Files changed:**
- `RateLimitFetcher.swift` — change return type to `FetchResult` enum, capture HTTP status
- `AppStore.swift` — add `staleProfileIds: Set<UUID>`, update on fetch
- `MenuContentView.swift` — add health indicator dot to profileRow

### 2. Auth Recovery

#### Problem
If `~/.codex/auth.json` is deleted, corrupted, or overwritten by external tools, CodexSwitcher doesn't detect it and continues operating under the assumption that the active account is valid.

#### Solution

**A. Boot-time recovery check (fixes C1 — runs BEFORE loadProfiles):**

```swift
enum AuthVerificationResult {
    case valid              // auth.json exists, parseable, matches active profile
    case recovered          // was broken, restored from profile's stored auth
    case unrecoverable      // both auth.json and profile auth missing
}
```

In `AppStore.init()`, the order is:
```swift
profileManager.bootstrap()
let recoveryResult = profileManager.verifyAndRecoverActiveAuth()  // ← BEFORE loadProfiles
loadProfiles()  // Now reads the corrected activeProfileId from config
```

`verifyAndRecoverActiveAuth()` in `ProfileManager`:
1. Read `config.json` to get `activeProfileId`
2. If no active profile → return `.valid` (nothing to verify)
3. Check `~/.codex/auth.json` exists and is valid JSON with `tokens.access_token`
4. If valid → extract `account_id`, compare with active profile's `accountId`
5. If mismatch or missing → copy active profile's auth file to `~/.codex/auth.json`
6. If profile's auth file also missing → return `.unrecoverable`

**B. Post-activate verification with disk-backed backup (fixes C3):**

Before `ProfileManager.activate(profile:)` writes the new auth.json:
1. Copy current `~/.codex/auth.json` to `~/.codex-switcher/auth-backup.json` (disk backup, survives crashes)
2. Perform atomic write of new auth
3. Read back and verify: file exists, valid JSON, `account_id` matches target profile
4. If verification succeeds → delete backup file
5. If verification fails → copy backup back to `~/.codex/auth.json` (rollback)

**C. External modification detection (fixes C2 — reuse existing authWatcher):**

The existing `authWatcher` in `AppStore` (used during add-account flow) is extended:
- When `isAddingAccount == true` → existing behavior (detect new login)
- When `isAddingAccount == false` → external modification detected → run `verifyActiveAuth()` and alert if mismatch
- Add 500ms debounce to prevent false positives from our own atomic writes

**Files changed:**
- `ProfileManager.swift` — add `verifyAndRecoverActiveAuth() -> AuthVerificationResult`, backup/rollback in `activate()`
- `AppStore.swift` — call `verifyAndRecoverActiveAuth()` before `loadProfiles()`, extend `authFileChanged()` for external modification detection
- No changes to `UsageMonitor.swift` (fixes C2, L4)

### 3. Switch Verification

#### Problem
After switching accounts, there's no confirmation that Codex is actually using the new account. The user must trust that the switch succeeded.

#### Solution

**Post-switch verification flow:**

`ProfileManager.verifyActiveAccount(expectedAccountId:) -> VerifyResult`:
```swift
enum VerifyResult {
    case verified
    case failed(VerifyError)
}

enum VerifyError {
    case fileMissing
    case invalidJSON
    case jwtParseFailed
    case claimNotFound
    case mismatch(expected: String, actual: String)
}
```

Steps in `activateCandidate()` (fixes H3):
1. Write new auth.json (with backup, see Auth Recovery section)
2. Call `verifyActiveAccount(expectedAccountId: candidate.accountId)`
3. If `.verified` → proceed normally
4. If `.failed` → one automatic retry: **re-read the file only** (fixes H4 — retry = re-read, not re-write, in case of race with external writer)
5. If retry also fails → rollback from backup, show "Switch failed" alert

**No persistent status bar indicator** (fixes L3). The status bar is already crowded with rate limit text. Verification status is shown transiently:
- Success → silent (no extra notification beyond existing "Account switched")
- Failure → existing "Switch failed" notification with error details

**Files changed:**
- `ProfileManager.swift` — add `verifyActiveAccount(expectedAccountId:) -> VerifyResult` with proper error types
- `AppStore.swift` — integrate verification + retry + rollback into `activateCandidate()`
- No changes to `CodexSwitcherApp.swift` (fixes L3)

### 4. Exhaustion UX

#### Problem
When all accounts are rate-limited (`allExhausted = true`), the user gets a notification but the popover UI doesn't clearly communicate the situation or what to do next.

#### Solution

**A. Exhaustion banner in popover:**
When `allExhausted == true`, show a red banner at the top of the main content area:
```
⚠️ Tüm hesapların limiti doldu
İlk sıfırlanacak: work@account.com — 14:30'da
[Yine de geç]
```

**Next reset logic** (fixes H5):
```swift
var nextResetInfo: (profileName: String, resetTime: String)? {
    // For each exhausted profile (limitReached == true), find earliest reset
    let exhaustedProfiles = profiles.filter { rateLimits[$0.id]?.limitReached == true }
    let resetTimes = exhaustedProfiles.compactMap { profile -> (String, Date)? in
        let rl = rateLimits[profile.id]
        let candidates = [rl?.weeklyResetAt, rl?.fiveHourResetAt].compactMap { $0 }
        guard let earliest = candidates.min() else { return nil }
        return (profile.displayName, earliest)
    }
    guard let (name, date) = resetTimes.min(by: { $0.1 < $1.1 }) else { return nil }
    let fmt = DateFormatter()
    fmt.dateFormat = date.isToday ? "HH:mm" : "d MMM HH:mm"
    return (name, fmt.string(from: date))
}
```

**B. Per-account exhaustion indicators:**
- Profiles with `limitReached = true` show a red lock icon (`lock.fill` SF Symbol)
- Show reset time next to exhausted accounts
- **No reordering** (fixes M3) — keep existing profile order, use visual indicators only. Active profile stays in its natural position.

**C. Manual override (fixes H6):**
The "Yine de geç" button in the exhaustion banner calls `switchToNext(reason: "Manuel override")` which bypasses `smartNextProfile(auto:)` and uses round-robin instead. This is already how `switchToNext(reason:)` works when `reason` doesn't contain "Limit" — the `isAuto` flag is `false`, so `smartNextProfile(auto: false)` does round-robin without filtering by exhaustion.

The switch event is logged with `reason: "Manuel override"` / `"Manual override"`.

**D. Status bar exhaustion indicator:**
Already implemented — `exclamationmark.circle.fill` icon when `allExhausted == true`. No changes needed.

**Files changed:**
- `MenuContentView.swift` — add exhaustion banner (shown when `store.allExhausted`), per-account lock icons, override button
- `AppStore.swift` — add `nextResetInfo` computed property
- `L10n.swift` — add TR/EN strings: exhaustion banner text, manual override, reset labels

## Data Flow Summary

```
App Launch
  → bootstrap() — create directories
  → verifyAndRecoverActiveAuth() — recover if auth.json broken (BEFORE loadProfiles)
  → loadProfiles() — reads corrected config
  → fetchAllRateLimits() — health + rate limit data

Popover Open
  → fetchAllRateLimits() — refresh health + rate limit data
  → show exhaustion banner if allExhausted

Rate Limit Detected (UsageMonitor)
  → smartNextProfile(auto: true) — skip exhausted accounts
  → activateCandidate() — backup → write auth.json → verify → rollback on fail
  → if verify fails → retry (re-read) → if still fails → rollback

Manual Switch
  → activateCandidate() — backup → write → verify → rollback on fail

Exhaustion State
  → show banner with next reset info + "Switch anyway" button
  → "Switch anyway" → round-robin to next account (bypasses exhaustion filter)

External auth.json Modification (when not adding account)
  → authWatcher fires → verifyActiveAuth() → alert if mismatch
```

## Error Handling

| Scenario | Recovery |
|----------|----------|
| auth.json missing on boot | Restore from active profile's stored auth → `.recovered` |
| auth.json corrupted on boot | Restore from active profile; if that fails too → `.unrecoverable`, mark all stale |
| `~/.codex/` directory missing | `bootstrap()` recreates it, then attempt recovery |
| auth.json is a broken symlink | Treated as missing → restore from profile |
| activate() writes bad file | Rollback from `auth-backup.json` on disk |
| verification mismatch | Re-read file (retry) → if still fails, rollback from backup |
| Two profiles with same accountId | Both shown independently; switching to either uses same auth (user's choice) |
| All accounts exhausted | Show banner with reset times, allow manual override |
| Network error during health check | Mark as unknown (gray), retry on next popover open |
| Stale token (401/403) | Mark profile as stale (yellow), suggest re-login via context menu |
| Health check during airplane mode | `.unknown` (gray) persists until next successful fetch |

## Testing Strategy

### Unit Tests
- `FetchResult` derivation from HTTP status codes (200→success, 401→stale, 503→failure)
- `verifyActiveAccount()` with valid/invalid/mismatched auth files
- `smartNextProfile()` with various exhaustion states
- Auth recovery logic (missing file, corrupted file, broken symlink, valid file)
- `nextResetInfo` computation with mixed free/plus accounts

### Integration Tests
- Full switch flow: backup → activate → verify → confirm
- Exhaustion detection and manual override
- Boot-time recovery with missing auth.json
- External auth.json modification detection (debounce behavior)

### Manual Testing
- Add 2+ accounts, exhaust one, verify auto-switch skips it
- Corrupt auth.json manually, restart app, verify recovery
- Switch while Codex is running, verify no stream disconnect
- Check health indicators update correctly on popover open
- Test with `~/.codex/` directory fully deleted
- Test with auth.json as a symlink to a deleted target
- Test health indicator during airplane mode (should show gray/unknown)
- Add the same account twice, verify both rows work independently

## Migration Notes

- No database schema changes
- No config format changes
- Existing `config.json` and profile auth files remain compatible
- New files created:
  - `~/.codex-switcher/auth-backup.json` — temporary, deleted after verification
  - `~/.codex-switcher/cache/` — already exists (from SessionTokenParser)

## Risks

| Risk | Mitigation |
|------|-----------|
| Health check API calls add latency | Parallel fetch (already implemented), 8s timeout |
| File watcher causes false positives | 500ms debounce, verify content not just event, skip during `isAddingAccount` |
| Backup file left on disk after crash | Clean up on next app launch (check if backup exists and verification passes → delete) |
| Exhaustion banner takes vertical space | Only show when `allExhausted == true`, compact one-line format |
| `FetchResult` enum breaks existing callers | Update all call sites in `AppStore.fetchAllRateLimits()` — single call site |
