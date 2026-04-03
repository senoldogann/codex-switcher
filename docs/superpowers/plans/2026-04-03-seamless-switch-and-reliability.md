# Seamless Switch And Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the current login/export/layout regressions, then add safe boundary switching and restart-free account rotation with reliability analytics.

**Architecture:** Keep the current menu bar app structure, but add focused orchestration models around switching instead of growing `AppStore` with more loose state. Implement in phases so phase 1 restores trust in the current UI and phase 2 introduces safe switching without breaking the existing fallback behavior.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Testing, existing Codex session parsing and profile/auth file management

---

## File Map

- Modify: `Sources/CodexSwitcher/AppStore.swift`
  - Login start fix
  - Safe switch state orchestration
  - Seamless verification and fallback path
- Modify: `Sources/CodexSwitcher/AddAccountInlineView.swift`
  - Explicit start/failure/loading states for login flow
- Modify: `Sources/CodexSwitcher/MenuContentView.swift`
  - Top/bottom spacing reduction
  - History tab bar fit and analytics/reliability summaries
- Modify: `Sources/CodexSwitcher/ProjectBreakdownView.swift`
  - Stable CSV export flow
- Create: `Sources/CodexSwitcher/ProjectCSVExporter.swift`
  - CSV formatting helper
- Modify: `Sources/CodexSwitcher/Models.swift`
  - Switch orchestration and reliability model types
- Modify: `Sources/CodexSwitcher/SessionTokenParser.swift`
  - Safe boundary signals, switch analytics data inputs
- Modify: `Sources/CodexSwitcher/UsageMonitor.swift`
  - Feed session activity timestamps used by safe switch logic
- Modify: `Sources/CodexSwitcher/ProfileManager.swift`
  - Auth rotation helpers needed for seamless verification
- Test: `Tests/CodexSwitcherTests/ProjectCSVExporterTests.swift`
- Create/Modify: `Tests/CodexSwitcherTests/SwitchOrchestrationTests.swift`
- Create/Modify: `Tests/CodexSwitcherTests/LoginFlowTests.swift`
- Modify: `README.md`
  - Changelog updates after implementation ships

### Task 1: Stabilize CSV Export

**Files:**
- Modify: `Sources/CodexSwitcher/ProjectBreakdownView.swift`
- Create: `Sources/CodexSwitcher/ProjectCSVExporter.swift`
- Test: `Tests/CodexSwitcherTests/ProjectCSVExporterTests.swift`

- [ ] **Step 1: Write the failing/export-format test**

Run or update:
```swift
@Test
func buildCSVQuotesFieldsAndFormatsRows()
```

- [ ] **Step 2: Run test to verify current gap**

Run:
```bash
swift test --filter ProjectCSVExporterTests
```

Expected: test fails until helper exists or export formatting is isolated.

- [ ] **Step 3: Add minimal CSV builder**

Create `ProjectCSVExporter.buildCSV(for:)` that:
- escapes quotes
- writes stable header
- writes newline-terminated output

- [ ] **Step 4: Move `ProjectBreakdownView` export to helper + modal save panel**

Implementation notes:
- use `NSSavePanel`
- activate app before presenting
- set `.commaSeparatedText`
- write error-safe path without silent no-op UI behavior

- [ ] **Step 5: Run focused and full tests**

Run:
```bash
swift test --filter ProjectCSVExporterTests
swift test
```

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexSwitcher/ProjectBreakdownView.swift Sources/CodexSwitcher/ProjectCSVExporter.swift Tests/CodexSwitcherTests/ProjectCSVExporterTests.swift
git commit -m "fix: restore projects csv export"
```

### Task 2: Fix Add Account Start Flow

**Files:**
- Modify: `Sources/CodexSwitcher/AppStore.swift`
- Modify: `Sources/CodexSwitcher/AddAccountInlineView.swift`
- Test: `Tests/CodexSwitcherTests/LoginFlowTests.swift`

- [ ] **Step 1: Write failing login-start tests**

Add tests for:
- start action invokes login launch path
- failure updates visible state
- success path enters waiting state

- [ ] **Step 2: Run test to verify failure**

Run:
```bash
swift test --filter LoginFlowTests
```

- [ ] **Step 3: Refactor login launch into injectable unit**

Implementation notes:
- isolate binary lookup + process launch
- expose deterministic state transitions for UI
- avoid hidden failure when process cannot start

- [ ] **Step 4: Update `AddAccountInlineView`**

Ensure `Start`:
- always triggers the store action
- disables correctly during launch
- shows explicit error/failure copy when launch fails

- [ ] **Step 5: Run focused and full tests**

Run:
```bash
swift test --filter LoginFlowTests
swift test
```

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexSwitcher/AppStore.swift Sources/CodexSwitcher/AddAccountInlineView.swift Tests/CodexSwitcherTests/LoginFlowTests.swift
git commit -m "fix: make add account login start reliably"
```

### Task 3: Tighten Vertical Layout And History Tabs

**Files:**
- Modify: `Sources/CodexSwitcher/MenuContentView.swift`

- [ ] **Step 1: Define compact spacing adjustments**

Reduce:
- top empty padding before first account card
- bottom idle gap above status strip
- history tab spacing and label squeeze

- [ ] **Step 2: Implement minimal layout changes**

Constraints:
- keep current glass style
- no new color system
- no new navigation concept

- [ ] **Step 3: Run build and regression tests**

Run:
```bash
swift build -c release
swift test
```

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexSwitcher/MenuContentView.swift
git commit -m "fix: tighten menu spacing and tab layout"
```

### Task 4: Introduce Switch Orchestration Models

**Files:**
- Modify: `Sources/CodexSwitcher/Models.swift`
- Modify: `Sources/CodexSwitcher/AppStore.swift`
- Test: `Tests/CodexSwitcherTests/SwitchOrchestrationTests.swift`

- [ ] **Step 1: Write failing state-machine tests**

Cover:
- idle -> pending when limit arrives during active work
- pending does not execute immediately
- pending stores target, reason, and timestamp

- [ ] **Step 2: Run focused test**

Run:
```bash
swift test --filter SwitchOrchestrationTests
```

- [ ] **Step 3: Add model types**

Create focused types for:
- switch orchestration state
- pending switch request
- seamless switch result
- reliability counters

- [ ] **Step 4: Wire state into `AppStore` without changing fallback logic yet**

- [ ] **Step 5: Re-run tests**

Run:
```bash
swift test --filter SwitchOrchestrationTests
swift test
```

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexSwitcher/Models.swift Sources/CodexSwitcher/AppStore.swift Tests/CodexSwitcherTests/SwitchOrchestrationTests.swift
git commit -m "feat: add switch orchestration state"
```

### Task 5: Add Safe Boundary Detection

**Files:**
- Modify: `Sources/CodexSwitcher/AppStore.swift`
- Modify: `Sources/CodexSwitcher/SessionTokenParser.swift`
- Modify: `Sources/CodexSwitcher/UsageMonitor.swift`
- Test: `Tests/CodexSwitcherTests/SwitchOrchestrationTests.swift`

- [ ] **Step 1: Extend tests for safe boundary transitions**

Cover:
- token activity keeps switch pending
- quiet period or request boundary makes switch ready

- [ ] **Step 2: Implement boundary signals**

Use:
- latest token activity time
- active-turn state
- parsed task boundary markers already available in logs

- [ ] **Step 3: Execute switch only when ready**

Keep current restart path as downstream fallback for now.

- [ ] **Step 4: Run tests**

Run:
```bash
swift test --filter SwitchOrchestrationTests
swift test
```

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexSwitcher/AppStore.swift Sources/CodexSwitcher/SessionTokenParser.swift Sources/CodexSwitcher/UsageMonitor.swift Tests/CodexSwitcherTests/SwitchOrchestrationTests.swift
git commit -m "feat: delay switching until safe boundary"
```

### Task 6: Add Seamless Switch Verification With Restart Fallback

**Files:**
- Modify: `Sources/CodexSwitcher/AppStore.swift`
- Modify: `Sources/CodexSwitcher/ProfileManager.swift`
- Modify: `Sources/CodexSwitcher/Models.swift`
- Test: `Tests/CodexSwitcherTests/SwitchOrchestrationTests.swift`

- [ ] **Step 1: Add failing tests for verification outcomes**

Cover:
- successful verification avoids restart
- failed verification falls back to restart
- inconclusive verification prefers safety

- [ ] **Step 2: Implement auth rotation + verification flow**

Behavior:
- rotate auth
- observe next request/account proof
- record result
- restart only on failure/inconclusive path if required

- [ ] **Step 3: Run tests**

Run:
```bash
swift test --filter SwitchOrchestrationTests
swift test
swift build -c release
```

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexSwitcher/AppStore.swift Sources/CodexSwitcher/ProfileManager.swift Sources/CodexSwitcher/Models.swift Tests/CodexSwitcherTests/SwitchOrchestrationTests.swift
git commit -m "feat: prefer seamless account switching"
```

### Task 7: Add Reliability And Switch Analytics

**Files:**
- Modify: `Sources/CodexSwitcher/AppStore.swift`
- Modify: `Sources/CodexSwitcher/MenuContentView.swift`
- Modify: `Sources/CodexSwitcher/Models.swift`
- Modify: `Sources/CodexSwitcher/SessionTokenParser.swift`
- Test: `Tests/CodexSwitcherTests/SwitchOrchestrationTests.swift`

- [ ] **Step 1: Add failing tests for counters/timeline**

Cover:
- pending duration tracked
- seamless success/failure counts tracked
- fallback count increments

- [ ] **Step 2: Implement counters and presentation summaries**

Keep UI compact and consistent with current design.

- [ ] **Step 3: Run tests and build**

Run:
```bash
swift test
swift build -c release
```

- [ ] **Step 4: Update changelog and commit**

```bash
git add Sources/CodexSwitcher/AppStore.swift Sources/CodexSwitcher/MenuContentView.swift Sources/CodexSwitcher/Models.swift Sources/CodexSwitcher/SessionTokenParser.swift README.md Tests/CodexSwitcherTests/SwitchOrchestrationTests.swift
git commit -m "feat: add switch reliability analytics"
```

### Task 8: Final Verification And Release Prep

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Run full verification**

```bash
swift test
swift build -c release
```

- [ ] **Step 2: Manual smoke test**

Check:
- Add Account start
- Projects CSV
- tighter layout
- pending switch behavior
- seamless next-request switch behavior

- [ ] **Step 3: Prepare release notes**

Update `README.md` changelog for the shipping version.

- [ ] **Step 4: Final commit if needed**

```bash
git add README.md
git commit -m "docs: update release notes for seamless switching"
```
