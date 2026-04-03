# Observability And Release Design

**Goal:** Improve in-app update visibility, health diagnostics, analytics filtering, parser test coverage, and release automation without changing the existing visual design language.

**Architecture:** Keep `AppStore` as the main orchestration layer, but introduce small supporting models for update status, rate limit health metadata, analytics time range, and fixture helpers so logic stays testable. Extend existing views with compact secondary UI rows and segmented-style controls rather than adding new layout systems or visual themes.

**Tech Stack:** Swift 6.2, SwiftUI, Foundation, AppKit, Swift Testing, GitHub CLI

---

## Scope

- Add in-app update status details: current version, latest version, last checked, and update state.
- Expose stale reason, last successful fetch, and fetch diagnostics for account health.
- Add analytics time filters for 7 days, 30 days, and all time.
- Expand parser and analytics test coverage with reusable fixtures.
- Add a single-command local release automation flow that builds, signs, notarizes, tags, and publishes GitHub releases.

## Non-Goals

- Redesign the menu bar UI, colors, spacing system, or navigation layout.
- Move signing/notarization secrets into CI.
- Re-architect the entire app away from `AppStore`.
- Add cloud telemetry or remote error reporting.

## Design

### 1. Update Status Visibility

- Extend `UpdateChecker` from a simple “new release or nil” API to a richer status response.
- Track:
  - running version
  - latest known version
  - last checked timestamp
  - release URL
  - fetch status (`upToDate`, `updateAvailable`, `checking`, `failed`)
- Render these details near the existing footer update control using the same typography, opacity, and spacing patterns already used in the app.

### 2. Health And Limit Diagnostics

- Replace bare `FetchResult` with a richer result carrying reason metadata.
- Capture:
  - stale reason (`unauthorized`, `forbidden`, invalid auth, etc.)
  - last successful fetch timestamp per profile
  - last failed fetch timestamp per profile
  - last HTTP status code / transport failure summary
- Show this only as compact secondary lines in each profile row and for stale profiles in context menus where useful.

### 3. Analytics Time Filtering

- Add a shared analytics range enum (`sevenDays`, `thirtyDays`, `allTime`).
- Filter parser-derived outputs at the source rather than bolting filtering onto each view separately.
- Apply the same selected range consistently to:
  - chart
  - projects
  - sessions
  - heatmap
  - top dollar
- Keep the visual control small and inline with the existing history tab header.

### 4. Parser Fixture Expansion

- Introduce reusable JSONL fixture builders instead of long inline arrays in every test.
- Cover:
  - multi-token turn accumulation
  - nested agent sessions
  - time-window filtering
  - heatmap bucket placement
  - project/session aggregation
  - update status transitions where feasible

### 5. Release Automation

- Add a new local script that orchestrates the full release flow in one command.
- Flow:
  - read version from `Info.plist`
  - optionally validate changelog entry exists
  - run tests
  - build signed/notarized app
  - create or update git tag
  - create GitHub release with notes and upload the signed zip
- Reuse `build_signed.sh` rather than duplicating signing logic.

## Files Expected To Change

- Modify: `Sources/CodexSwitcher/UpdateChecker.swift`
- Modify: `Sources/CodexSwitcher/AppStore.swift`
- Modify: `Sources/CodexSwitcher/MenuContentView.swift`
- Modify: `Sources/CodexSwitcher/RateLimitFetcher.swift`
- Modify: `Sources/CodexSwitcher/Models.swift`
- Modify: `Sources/CodexSwitcher/UsageChartView.swift`
- Modify: `Sources/CodexSwitcher/ProjectBreakdownView.swift`
- Modify: `Sources/CodexSwitcher/SessionExplorerView.swift`
- Modify: `Sources/CodexSwitcher/HeatmapView.swift`
- Modify: `Sources/CodexSwitcher/ExpensivePromptsView.swift`
- Add: `Tests/CodexSwitcherTests/Support/SessionFixture.swift`
- Modify: parser/analytics tests under `Tests/CodexSwitcherTests/`
- Add: `scripts/release.sh`
- Modify: `README.md`

## Testing Strategy

- Write failing tests before each behavioral change.
- Run focused `swift test` during implementation.
- Run full `swift test` and `swift build -c release` before completion.
- Dry-run release automation enough to verify command composition and asset path handling.

## Risks And Mitigations

- **Risk:** `AppStore` becomes too state-heavy.
  - **Mitigation:** add focused helper models and avoid embedding raw dictionaries directly into view code.
- **Risk:** analytics filters diverge across views.
  - **Mitigation:** centralize time-range filtering in parser/store helpers.
- **Risk:** release script accidentally creates inconsistent tags/releases.
  - **Mitigation:** make version read-only from `Info.plist` and validate tag/version match before publishing.

## Acceptance Criteria

- Update area shows current version, latest version, and last checked time.
- Stale profiles show actionable diagnostic context.
- History analytics support 7d, 30d, and all-time filtering consistently.
- Parser coverage expands with reusable fixtures.
- A single local command can produce the signed asset and publish the GitHub release.
