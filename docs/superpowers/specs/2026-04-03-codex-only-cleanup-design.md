# Codex-Only Cleanup Design

**Goal:** Remove Claude Code support entirely so CodexSwitcher becomes a Codex-only app in code, UI, local data migration, documentation, and release messaging.

**Architecture:** Collapse the app from a dual-provider model to a single Codex flow. Remove provider branching from state, profile management, and views; migrate persisted config by filtering Claude profiles and deleting Claude-specific stored auth artifacts during bootstrap/load.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, Swift Package Manager, GitHub CLI

---

## Scope

- Remove Claude Code support from runtime code paths, data model, auth handling, and UI.
- Remove Claude-specific stored profile artifacts from local app state.
- Keep all Codex functionality intact, including rate limits, switching, insights, and Top `$` fixes already in progress.
- Update README and release notes to describe a Codex-only product.
- Create the next GitHub release after verification.

## Non-Goals

- Preserve backward compatibility for Claude profiles.
- Keep dormant Claude code behind flags.
- Refactor unrelated analytics, update-checker, or switching behavior beyond what removal requires.

## Design

### 1. Data Model Simplification

- Replace the multi-provider `AIProvider` model with Codex-only semantics.
- Remove Claude-only enum cases, labels, process names, and login commands.
- Keep profile decoding backward-compatible enough to load older config files, but filter out any stored `claudeCode` entries during config/bootstrap so they are not surfaced in memory or re-saved.

### 2. Local Data Migration

- During startup/config normalization, remove Claude profiles from persisted config.
- Delete Claude-specific stored auth files (`*.claudeauth`) associated with removed profiles.
- Ensure `activeProfileId` is reassigned safely if the old active profile was Claude.
- Migration should be idempotent: running again should not change already-clean state.

### 3. Auth and Switching Cleanup

- Remove `ClaudeCodeManager.swift` entirely.
- Remove Claude-specific capture, activation, verification, polling, restart notification, and add-account flows from `ProfileManager.swift` and `AppStore.swift`.
- Leave a single Codex auth path centered on `~/.codex/auth.json`.

### 4. UI Cleanup

- Remove provider picker branching and Claude-specific visuals from account add flow and account list rows.
- Remove Claude badges, Claude avatar, Claude info row, and Claude health/status exceptions.
- Keep the UI behavior identical for Codex accounts.

### 5. Documentation and Release

- Rewrite README sections that mention dual-provider support, Claude installation/login, and Claude architecture.
- Add a changelog entry for the Codex-only release.
- Create the next release as `v1.15.0` after tests/build pass and the repo state is ready.

## Files Expected To Change

- Modify: `Sources/CodexSwitcher/Models.swift`
- Modify: `Sources/CodexSwitcher/ProfileManager.swift`
- Modify: `Sources/CodexSwitcher/AppStore.swift`
- Modify: `Sources/CodexSwitcher/MenuContentView.swift`
- Modify: `Sources/CodexSwitcher/AddAccountInlineView.swift`
- Delete: `Sources/CodexSwitcher/ClaudeCodeManager.swift`
- Modify: `README.md`
- Modify: `Package.swift` only if tests/resources need adjustment
- Add/modify tests under `Tests/CodexSwitcherTests/`

## Testing Strategy

- Add regression tests for config migration/filtering of Claude profiles.
- Add tests for idempotent cleanup of Claude artifacts if feasible through `ProfileManager` seams.
- Run `swift test`.
- Run `swift build`.
- Review final diff before commit/release.

## Risks and Mitigations

- **Risk:** Old config contains Claude as active profile and app ends up with no valid active account.
  - **Mitigation:** Normalize config on load and reassign `activeProfileId` to the first remaining Codex profile or `nil`.
- **Risk:** UI assumptions still reference provider branching.
  - **Mitigation:** Remove branching entirely instead of leaving dead conditions.
- **Risk:** Release notes and README drift from actual shipped behavior.
  - **Mitigation:** Update docs only after code cleanup is complete and verified.

## Acceptance Criteria

- No Claude Code references remain in shipped app code or README.
- App runs as Codex-only without provider branching.
- Existing stored Claude profiles are removed automatically on startup.
- `swift test` passes.
- `swift build` passes.
- GitHub release `v1.15.0` is created with Codex-only release notes.
