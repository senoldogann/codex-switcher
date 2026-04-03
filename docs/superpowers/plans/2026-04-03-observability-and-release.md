# Observability And Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add update visibility, health diagnostics, analytics time filters, broader parser fixtures, and one-command release automation while preserving the current UI design.

**Architecture:** Extend the existing store/parser/fetcher pipeline with compact supporting models instead of redesigning the app. Keep the UI structure intact and feed new metadata into existing views with minimal, low-contrast additions that match the current styling.

**Tech Stack:** Swift 6.2, SwiftUI, Foundation, AppKit, Swift Testing, GitHub CLI

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/CodexSwitcher/Models.swift` | Modify | Add shared models/enums for analytics range, update state, and health diagnostics |
| `Sources/CodexSwitcher/UpdateChecker.swift` | Modify | Return rich update status including current/latest version and last checked |
| `Sources/CodexSwitcher/RateLimitFetcher.swift` | Modify | Return fetch diagnostics and stale reasons |
| `Sources/CodexSwitcher/AppStore.swift` | Modify | Orchestrate update state, health metadata, analytics filtering, and diagnostics |
| `Sources/CodexSwitcher/MenuContentView.swift` | Modify | Show update details and account health diagnostics with existing styling |
| `Sources/CodexSwitcher/UsageChartView.swift` | Modify | Consume filtered analytics range |
| `Sources/CodexSwitcher/ProjectBreakdownView.swift` | Modify | Consume filtered analytics range |
| `Sources/CodexSwitcher/SessionExplorerView.swift` | Modify | Consume filtered analytics range |
| `Sources/CodexSwitcher/HeatmapView.swift` | Modify | Consume filtered analytics range |
| `Sources/CodexSwitcher/ExpensivePromptsView.swift` | Modify | Consume filtered analytics range |
| `Tests/CodexSwitcherTests/Support/SessionFixture.swift` | Create | Shared fixture builders for JSONL/session test data |
| `Tests/CodexSwitcherTests/*.swift` | Modify/Create | Regression coverage for parser, filters, update state, and fetch diagnostics |
| `scripts/build_signed.sh` | Modify | Keep as focused signing/notarization primitive |
| `scripts/release.sh` | Create | One-command release automation |
| `README.md` | Modify | Document update diagnostics and release flow |

## Task 1: Add shared models for update state, analytics range, and health diagnostics

**Files:**
- Modify: `Sources/CodexSwitcher/Models.swift`
- Test: no new test yet, compile coverage comes in later tasks

- [ ] **Step 1: Add `AnalyticsTimeRange` enum**
- [ ] **Step 2: Add `UpdateStatusSnapshot` and `UpdateCheckState` models**
- [ ] **Step 3: Add `RateLimitHealthStatus` / stale-reason model for per-profile diagnostics**
- [ ] **Step 4: Run `swift test` to verify compile integrity**
- [ ] **Step 5: Commit**

## Task 2: Expand update checker into a rich status source

**Files:**
- Modify: `Sources/CodexSwitcher/UpdateChecker.swift`
- Test: `Tests/CodexSwitcherTests/UpdateCheckerTests.swift`

- [ ] **Step 1: Write failing tests for version comparison and status mapping**
- [ ] **Step 2: Add decoding/helpers for latest release metadata**
- [ ] **Step 3: Return a full snapshot instead of only optional release**
- [ ] **Step 4: Run focused `swift test --filter UpdateCheckerTests`**
- [ ] **Step 5: Commit**

## Task 3: Add rate-limit fetch diagnostics and stale reasons

**Files:**
- Modify: `Sources/CodexSwitcher/RateLimitFetcher.swift`
- Modify: `Sources/CodexSwitcher/AppStore.swift`
- Test: `Tests/CodexSwitcherTests/RateLimitFetcherTests.swift`

- [ ] **Step 1: Write failing tests for stale reason and last-result mapping**
- [ ] **Step 2: Extend fetch result to carry status and timing metadata**
- [ ] **Step 3: Store per-profile last success/failure metadata in `AppStore`**
- [ ] **Step 4: Run focused fetch/store tests**
- [ ] **Step 5: Commit**

## Task 4: Add update details and health diagnostics to the existing UI

**Files:**
- Modify: `Sources/CodexSwitcher/MenuContentView.swift`

- [ ] **Step 1: Add compact update detail row near the existing update button**
- [ ] **Step 2: Add compact stale/last-fetch diagnostics under profile rows**
- [ ] **Step 3: Keep existing typography, opacity, spacing, and colors unchanged except existing semantic colors**
- [ ] **Step 4: Run `swift test` and `swift build`**
- [ ] **Step 5: Commit**

## Task 5: Add shared analytics time filtering

**Files:**
- Modify: `Sources/CodexSwitcher/AppStore.swift`
- Modify: `Sources/CodexSwitcher/SessionTokenParser.swift`
- Modify: `Sources/CodexSwitcher/UsageChartView.swift`
- Modify: `Sources/CodexSwitcher/ProjectBreakdownView.swift`
- Modify: `Sources/CodexSwitcher/SessionExplorerView.swift`
- Modify: `Sources/CodexSwitcher/HeatmapView.swift`
- Modify: `Sources/CodexSwitcher/ExpensivePromptsView.swift`
- Modify: `Sources/CodexSwitcher/MenuContentView.swift`
- Test: parser/analytics tests

- [ ] **Step 1: Write failing parser/store tests for 7d/30d/all-time filtering**
- [ ] **Step 2: Centralize filtering in parser/store helpers**
- [ ] **Step 3: Add a compact range selector in the history area**
- [ ] **Step 4: Move each analytics view to filtered inputs**
- [ ] **Step 5: Run full analytics test set**
- [ ] **Step 6: Commit**

## Task 6: Introduce reusable fixture helpers and broaden regression coverage

**Files:**
- Create: `Tests/CodexSwitcherTests/Support/SessionFixture.swift`
- Modify: `Tests/CodexSwitcherTests/TopDollarInsightsTests.swift`
- Modify/Create: additional parser and UI-independent logic tests

- [ ] **Step 1: Extract reusable JSONL/session fixture builders**
- [ ] **Step 2: Rewrite existing inline fixtures to use shared helpers**
- [ ] **Step 3: Add coverage for nested sessions, multi-turn windows, and range filters**
- [ ] **Step 4: Run full `swift test`**
- [ ] **Step 5: Commit**

## Task 7: Add one-command release automation

**Files:**
- Create: `scripts/release.sh`
- Modify: `scripts/build_signed.sh`
- Modify: `README.md`

- [ ] **Step 1: Write a shell-level dry-run plan and version/tag validation rules**
- [ ] **Step 2: Implement `scripts/release.sh` to run tests, build, tag, and publish**
- [ ] **Step 3: Reuse notarized zip from `build_signed.sh` instead of duplicating packaging logic**
- [ ] **Step 4: Document the release command in `README.md`**
- [ ] **Step 5: Dry-run non-destructive parts, then run full verification**
- [ ] **Step 6: Commit**

## Final Verification

- [ ] **Step 1: Run `swift test`**
- [ ] **Step 2: Run `swift build -c release`**
- [ ] **Step 3: Review `git diff --stat` and `git status --short`**
- [ ] **Step 4: Summarize risks, if any remain**
