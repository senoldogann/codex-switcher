# Reconciliation Ledger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a forensic reconciliation ledger that compares provider-side limit deltas with local Codex usage and explains why each drain window is classified as explained, weak, unexplained, idle, or ignored.

**Architecture:** Introduce a pure reconciliation model and a pure reconciliation engine, then feed those outputs into `AnalyticsSnapshot`, export, and the analytics window. Keep parser attribution, provider sample handling, and UI rendering as separate responsibilities so each rule is testable without SwiftUI or network coupling.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, local JSONL session parsing, local JSON/CSV export.

---

## Phase 1: Reconciliation Contracts and Policy

**Goal**
Define the ledger row model, summary model, status/reason enums, and policy knobs before touching UI or alert behavior.

**Tasks**
- [x] Add `ReconciliationEntry`, `ReconciliationSummary`, `ReconciliationStatus`, `ReconciliationReasonCode`, and `ReconciliationConfidence` to a dedicated model file.
- [x] Add a small immutable `ReconciliationPolicy` with `skewToleranceSeconds`, `minDrainPercent`, `minFiveHourDrainPercent`, and `lowLocalTokenThreshold`.
- [x] Decide which fields are export-safe by default and exclude sensitive prompt text from this phase.
- [x] Map current `AnalyticsUsageAudit*` fields to the new ledger model and identify what can be retired after migration.

**Entry Gate**
- [x] Product direction selected: `Trust / Forensic Audit`
- [x] Phase-1 scope selected: `provider delta vs local usage reconciliation`
- [x] Required ledger columns approved: account, window, provider delta, local tokens, matched sessions, status, reason code, confidence

**Test Gate**
- [x] Unit tests cover enum encoding/stability and summary aggregation.
- [x] Unit tests cover policy defaults and threshold behavior.
- [x] No UI or exporter depends on ad hoc string labels for status/reason decisions.

**Exit Gate**
- [x] Ledger contracts compile and are isolated from SwiftUI.
- [x] Policy defaults are explicit and covered by tests.
- [x] Sensitive fields intentionally excluded from the new model surface.

**Completion Log**
- [x] Status: Completed
- [x] Completed: Added `ReconciliationModels.swift` with ledger enums, entry/summary contracts, immutable policy defaults, and a legacy audit entry bridge for migration.
- [x] Test Evidence: `swift test --filter ReconciliationModelsTests` passed with 4 tests; `swift test` passed with 54 tests; `swift build -c release` passed; `git diff --check` clean.
- [x] Known Gaps: Phase 1 intentionally does not wire the ledger into `AnalyticsSnapshot`, export, or SwiftUI yet; that is Phase 2/3 scope. E2E UI validation is deferred until ledger UI exists in Phase 4.
- [x] Next Phase: Phase 2 — implement `ReconciliationEngine` with deterministic sample-window matching, missing-sample/reset handling, single-window local record assignment, and reason/confidence generation.

---

## Phase 2: Reconciliation Engine

**Goal**
Implement deterministic matching between provider sample windows and local usage records, including skew tolerance, single-window assignment, ignored/reset handling, and reason-code generation.

**Tasks**
- [x] Add `ReconciliationEngine` as a pure stateless service.
- [x] Build one window per consecutive provider sample pair and skip windows before the selected range cutoff.
- [x] Match local usage records to the closest eligible window within `±skewToleranceSeconds`.
- [x] Ensure one local usage record contributes to at most one window.
- [x] Compute provider weekly/five-hour deltas without converting missing optional percentages to `0`.
- [x] Emit `ignored + missing_provider_sample` when the current/previous sample is incomplete.
- [x] Emit `ignored + sample_reset_or_counter_jump` when provider percentages move upward in a way that indicates reset/counter discontinuity.
- [x] Emit `explained`, `weakAttribution`, or `unexplained` using local token volume, idle detection, and switch-boundary proximity.
- [x] Produce a `ReconciliationSummary` from the generated entries.

**Entry Gate**
- [x] Phase 1 exit gate passed.
- [x] Current `AnalyticsEngine.makeUsageAuditEntries` behavior reviewed as migration input.
- [x] Existing parser attribution fixes are present on the branch.

**Test Gate**
- [x] Unit: no-history active profile usage remains attributed.
- [x] Unit: missing provider sample fields produce `ignored`, not false drain.
- [x] Unit: reset/counter jumps produce `ignored + sample_reset_or_counter_jump`.
- [x] Unit: one local record is assigned to only one nearest window under skew tolerance.
- [x] Unit: low local tokens plus meaningful provider delta produce `weakAttribution`.
- [x] Unit: zero local tokens plus provider delta produce `unexplained` and `idle_drain` when no sessions exist.

**Exit Gate**
- [x] Engine output is deterministic for a fixed input set.
- [x] False positives from missing sample fields and reset jumps are covered by tests.
- [x] No reconciliation logic lives in SwiftUI views.

**Completion Log**
- [x] Status: Completed
- [x] Completed: Added `ReconciliationEngine.swift`, `ReconciliationReport`, and unit coverage for missing-sample, reset jump, cutoff/noise-floor, weak attribution, idle drain, and single-window local record assignment.
- [x] Test Evidence: `swift test --filter ReconciliationEngineTests` passed with 6 tests; `swift test` passed with 60 tests; `swift build -c release` passed; `git diff --check` clean.
- [x] Known Gaps: Engine output is not yet wired into `AnalyticsSnapshot`, alert selection, or CSV/JSON export. Phase 2 uses profile display names and session IDs only; prompt text and local paths remain intentionally excluded.
- [x] Next Phase: Phase 3 — extend `AnalyticsSnapshot`, derive alerts from `ReconciliationReport`, and add ledger-safe JSON/CSV export fields plus compatibility tests.

---

## Phase 3: Snapshot, Alerts, and Export Integration

**Goal**
Promote the ledger into `AnalyticsSnapshot`, make alerts derive from ledger rows, and extend CSV/JSON export with summary, entries, matched sessions, and policy metadata.

**Tasks**
- [x] Extend `AnalyticsSnapshot` with `reconciliationSummary`, `reconciliationEntries`, and active `reconciliationPolicy`.
- [x] Replace existing `usageAuditEntries` alert sourcing with ledger-derived entries.
- [x] Keep compatibility shims only if needed for a short migration step, then remove them.
- [x] Extend JSON export with summary, full entry rows, matched session IDs, reason codes, confidence, and policy values.
- [x] Extend CSV export with the ledger table columns and stable machine-readable reason/status values.
- [x] Redact or omit local prompt text and full project paths from export unless explicitly needed later.

**Entry Gate**
- [x] Phase 2 exit gate passed.
- [x] New ledger model and engine outputs are stable enough for snapshot wiring.
- [x] Existing export code paths reviewed for backward-compatibility impact.

**Test Gate**
- [x] Integration: parser + reconciliation engine + `AnalyticsEngine.makeSnapshot` produce consistent ledger rows from one fixture.
- [x] Unit: unexplained ledger rows emit the expected alert kind/severity/title.
- [x] Unit: ignored rows do not emit false suspicious-drain alerts.
- [x] Unit: JSON/CSV export includes ledger fields and omits prompt text by default.
- [x] Build: `swift build -c release` passes.

**Exit Gate**
- [x] Snapshot is the single read model for ledger UI and alerts.
- [x] Export contains enough forensic evidence to audit a drain window offline.
- [x] Legacy audit structures are either removed or clearly bounded as temporary compatibility.

**Completion Log**
- [x] Status: Completed
- [x] Completed: Wired `ReconciliationReport` into `AnalyticsSnapshot`, switched suspicious-drain alerts to ledger rows, added export-safe reconciliation JSON/CSV payloads, kept a bounded legacy audit bridge for existing UI/export compatibility, and fixed a cutoff regression so crossing windows are retained when the current sample is inside range.
- [x] Test Evidence: `swift test` passed with 65 tests; `swift build -c release` passed; `git diff --check` clean.
- [x] Known Gaps: Ledger UI and row drilldown are still on the old audit presentation surface; Phase 4 needs to render `reconciliationEntries` directly. Legacy `AnalyticsUsageAudit*` shims remain intentionally in place until the UI migration is complete.
- [x] Next Phase: Phase 4 — build the ledger UI, summary strip, and selected-row drilldown on top of `reconciliationEntries` without introducing heavy SwiftUI recomputation.

---

## Phase 4: Ledger UI and Drilldown

**Goal**
Turn the current audit card into a readable forensic ledger with summary pills, sortable row list, and one-row detail inspection, without overbuilding a heavy table framework.

**Tasks**
- [ ] Replace the current audit list with a ledger section backed by `reconciliationEntries`.
- [ ] Show summary pills for explained, weak, unexplained, idle, and ignored windows.
- [ ] Render each row with account, window, provider delta, local tokens, matched sessions count, status, reason, and confidence.
- [ ] Add a lightweight selected-row detail panel showing matched session IDs, skew/boundary note, and reason explanation.
- [ ] Make suspicious states visually distinct while keeping ignored/reset rows visible but lower priority.
- [ ] Preserve current dark/light styling and avoid expensive per-row computation inside SwiftUI `body`.

**Entry Gate**
- [ ] Phase 3 exit gate passed.
- [ ] UX copy for status/reason labels mapped from machine-readable enums.
- [ ] Sensitive export/display policy confirmed: no prompt text in this phase.

**Test Gate**
- [ ] Unit: view label mapping for reason/status/confidence remains stable.
- [ ] Integration: ledger section renders empty, explained, unexplained, and ignored states from fixture snapshots.
- [ ] E2E/manual: suspicious drain row can be selected, detail is readable, and export still works.
- [ ] Performance: no obvious `ForEach` identity churn or repeated sorting/filtering in `body`.

**Exit Gate**
- [ ] A user can answer “why was this window classified this way?” from the ledger UI alone.
- [ ] No new heavy SwiftUI invalidation pattern is introduced.
- [ ] `swift test` and `swift build -c release` pass.

**Completion Log**
- [ ] Status:
- [ ] Completed:
- [ ] Test Evidence:
- [ ] Known Gaps:
- [ ] Next Phase:

---

## Phase 5: Cleanup, Review, and Release Readiness

**Goal**
Remove temporary bridges, run the full quality loop, update docs, and prepare the feature branch for merge/release.

**Tasks**
- [ ] Remove superseded `AnalyticsUsageAudit*` types and helpers if the ledger fully replaces them.
- [ ] Re-scan the diff for secret leakage, overexposed local paths, and unsafe export content.
- [ ] Refactor any files that grew past a maintainable size, but only where directly touched by this feature.
- [ ] Update README/release notes with the ledger feature and its known limits.
- [ ] Run the full verification suite and capture exact evidence in the completion log.

**Entry Gate**
- [ ] Phase 4 exit gate passed.
- [ ] No unresolved correctness blockers remain in parser attribution or provider delta handling.

**Test Gate**
- [ ] Security: review export surfaces and user-facing errors for sensitive-data leakage.
- [ ] TDD: all new tests pass and regression tests remain green.
- [ ] Build Fix: `swift test` and `swift build -c release` pass on a fresh run.
- [ ] Review: inspect `git diff` for maintainability and correctness regressions.
- [ ] Refactor: targeted cleanup only, no scope expansion.
- [ ] E2E: manually validate ledger UI, export, and suspicious-drain display on the built app.

**Exit Gate**
- [ ] Branch is ready for push/release with a clear commit history.
- [ ] Completion logs are filled for all phases.
- [ ] Known limitations are documented, especially that provider internals are inferred from exposed samples and local logs, not reverse-engineered billing internals.

**Completion Log**
- [ ] Status:
- [ ] Completed:
- [ ] Test Evidence:
- [ ] Known Gaps:
- [ ] Next Phase:
