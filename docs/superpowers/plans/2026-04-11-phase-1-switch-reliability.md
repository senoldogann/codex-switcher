# Phase 1 Switch Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Phase 1 reliability foundation for CodexSwitcher so switch attempts become preflighted, explainable, and safely observable without depending on future diagnostics phases.

**Architecture:** Introduce a dedicated reliability domain around switching with typed decision records, readiness evaluation, and explicit orchestration outcomes. Keep the current local-first flow, but extract candidate evaluation and decision evidence out of `AppStore` so UI state and persistence consume consistent reliability records.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftUI, Foundation, AppKit

---

## File Structure

### Create

- `Sources/CodexSwitcher/SwitchReliabilityModels.swift`
  Defines typed reliability records for candidate readiness, switch decisions, rejection reasons, and persisted switch decision history.
- `Sources/CodexSwitcher/SwitchReadinessEvaluator.swift`
  Evaluates profile readiness using existing rate-limit, stale-auth, and active-profile state.
- `Sources/CodexSwitcher/SwitchDecisionStore.swift`
  Persists bounded switch decision records under `~/.codex-switcher`.
- `Tests/CodexSwitcherTests/SwitchReadinessEvaluatorTests.swift`
  Verifies the new readiness scoring and rejection reasoning with real domain values.
- `Tests/CodexSwitcherTests/SwitchDecisionStoreTests.swift`
  Verifies persistence round-trip and cap behavior for decision records.

### Modify

- `Sources/CodexSwitcher/Models.swift`
  Remove or slim only the switch-related types that should move into the new reliability models file.
- `Sources/CodexSwitcher/SwitchDecisionPolicy.swift`
  Narrow the policy to threshold rules and candidate ordering; let readiness evaluation produce richer decision context.
- `Sources/CodexSwitcher/SwitchOrchestrator.swift`
  Track structured decision outcomes and explicit failure / halt reasons rather than only timeline stages.
- `Sources/CodexSwitcher/AppStore.swift`
  Route manual and automatic switching through readiness evaluation, persist decision records, and expose them for UI consumption.
- `Sources/CodexSwitcher/AppStore+SeamlessSwitch.swift`
  Integrate pending-switch and verification transitions with the new decision/evidence records.
- `Sources/CodexSwitcher/AutomationConfidenceCalculator.swift`
  Fold blocked decisions and safe-halt outcomes into the reliability summary and account-level signals.
- `Sources/CodexSwitcher/MenuContentView+HistoryContent.swift`
  Show the new decision reasons and blocked-attempt context without overwhelming the current history layout.
- `Tests/CodexSwitcherTests/SwitchDecisionPolicyTests.swift`
  Update policy tests to fit the narrower boundary.
- `Tests/CodexSwitcherTests/SwitchOrchestratorTests.swift`
  Extend orchestration tests for structured failure and halt outcomes.
- `Tests/CodexSwitcherTests/AutomationConfidenceTests.swift`
  Verify that decision outcomes affect automation health correctly.
- `Tests/CodexSwitcherTests/AppStoreSwitchCoordinatorTests.swift`
  Cover preflight decision persistence and activation ordering with a focused integration-style test.

## Task 1: Introduce Reliability Domain Models

**Files:**
- Create: `Sources/CodexSwitcher/SwitchReliabilityModels.swift`
- Modify: `Sources/CodexSwitcher/Models.swift`
- Test: `Tests/CodexSwitcherTests/SwitchOrchestratorTests.swift`

- [ ] **Step 1: Define the new reliability record set**

Add explicit models for:

- `SwitchCandidateReadiness`
- `SwitchReadinessReason`
- `SwitchDecisionRecord`
- `SwitchDecisionOutcome`
- `SwitchDecisionSource`

The records must be `Codable` and `Equatable` where persistence or testing needs them.

- [ ] **Step 2: Move or split switch-related types cleanly**

Move new reliability-specific types into `SwitchReliabilityModels.swift` and keep `Models.swift` focused on shared app models.

- [ ] **Step 3: Wire minimal compile-safe references**

Update imports and references so the project still builds before behavior changes start.

- [ ] **Step 4: Run targeted verification**

Run: `swift test --filter SwitchOrchestratorTests`
Expected: existing orchestrator tests still pass after the type move.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexSwitcher/SwitchReliabilityModels.swift Sources/CodexSwitcher/Models.swift Tests/CodexSwitcherTests/SwitchOrchestratorTests.swift
git commit -m "refactor: split switch reliability models"
```

## Task 2: Add Readiness Evaluation

**Files:**
- Create: `Sources/CodexSwitcher/SwitchReadinessEvaluator.swift`
- Modify: `Sources/CodexSwitcher/SwitchDecisionPolicy.swift`
- Test: `Tests/CodexSwitcherTests/SwitchReadinessEvaluatorTests.swift`
- Test: `Tests/CodexSwitcherTests/SwitchDecisionPolicyTests.swift`

- [ ] **Step 1: Write the failing readiness tests**

Cover these cases:

- active profile is never a candidate
- stale auth reduces readiness and produces an explicit reason
- missing rate-limit data remains allowed but lower-confidence
- exhausted or near-threshold targets are rejected with explicit reasons
- among safe candidates, the best target remains deterministic

- [ ] **Step 2: Run the failing tests**

Run: `swift test --filter SwitchReadinessEvaluatorTests`
Expected: FAIL because evaluator does not exist yet.

- [ ] **Step 3: Implement readiness evaluation**

Create a focused evaluator that takes:

- profiles
- active profile id
- rate limits
- stale profile ids
- optional recent reliability pressure

Return one readiness record per profile plus a deterministic preferred candidate.

- [ ] **Step 4: Narrow the decision policy**

Keep `SwitchDecisionPolicy` focused on threshold semantics and ordering helpers. Do not duplicate readiness scoring logic there.

- [ ] **Step 5: Re-run targeted tests**

Run: `swift test --filter SwitchReadinessEvaluatorTests`
Expected: PASS

Run: `swift test --filter SwitchDecisionPolicyTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexSwitcher/SwitchReadinessEvaluator.swift Sources/CodexSwitcher/SwitchDecisionPolicy.swift Tests/CodexSwitcherTests/SwitchReadinessEvaluatorTests.swift Tests/CodexSwitcherTests/SwitchDecisionPolicyTests.swift
git commit -m "feat: add switch readiness evaluation"
```

## Task 3: Persist Decision Records

**Files:**
- Create: `Sources/CodexSwitcher/SwitchDecisionStore.swift`
- Test: `Tests/CodexSwitcherTests/SwitchDecisionStoreTests.swift`

- [ ] **Step 1: Write the failing persistence tests**

Cover:

- append and load round-trip
- bounded max history behavior
- empty-store load behavior

- [ ] **Step 2: Run the failing tests**

Run: `swift test --filter SwitchDecisionStoreTests`
Expected: FAIL because the store does not exist yet.

- [ ] **Step 3: Implement the store**

Persist JSON records in `~/.codex-switcher/switch-decisions.json` with explicit encoder/decoder date handling and bounded retention similar to existing history stores.

Require `SwitchDecisionStore.init(baseDirectory:)` so tests can use temporary directories.

- [ ] **Step 4: Re-run targeted tests**

Run: `swift test --filter SwitchDecisionStoreTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexSwitcher/SwitchDecisionStore.swift Tests/CodexSwitcherTests/SwitchDecisionStoreTests.swift
git commit -m "feat: persist switch decision records"
```

## Task 4: Integrate Reliability Decisions Into AppStore

**Files:**
- Modify: `Sources/CodexSwitcher/AppStore.swift`
- Modify: `Sources/CodexSwitcher/AppStore+SeamlessSwitch.swift`
- Modify: `Sources/CodexSwitcher/SwitchOrchestrator.swift`
- Modify: `Sources/CodexSwitcher/AutomationConfidenceCalculator.swift`
- Modify: `Sources/CodexSwitcher/Models.swift`
- Test: `Tests/CodexSwitcherTests/SwitchOrchestratorTests.swift`
- Test: `Tests/CodexSwitcherTests/AutomationConfidenceTests.swift`
- Test: `Tests/CodexSwitcherTests/AppStoreSwitchCoordinatorTests.swift`

- [ ] **Step 1: Add app state for decision records**

Expose bounded in-memory decision history in `AppStore` backed by `SwitchDecisionStore`.

- [ ] **Step 2: Preflight manual and automatic switch paths**

Before activation:

- evaluate readiness
- persist a decision record
- hard-block unsafe automatic targets with explicit user-facing feedback
- preserve a manual override path for unsafe manual targets while still recording warning evidence
- keep analytics attribution clean by writing switch history only after verified activation

- [ ] **Step 3: Extend orchestration outcomes**

Track:

- queued decision
- executed decision
- blocked decision
- verification fallback
- safe halt when no acceptable target exists

Do not depend on Phase 2 log correlation.

- [ ] **Step 4: Keep pending-switch behavior deterministic**

When session activity blocks an automatic switch, preserve the evaluated target and reason in the decision record so later execution is explainable.

- [ ] **Step 5: Re-run targeted tests**

Run: `swift test --filter SwitchOrchestratorTests`
Expected: PASS

Run: `swift test --filter AutomationConfidenceTests`
Expected: PASS

Run: `swift test --filter AppStoreSwitchCoordinatorTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexSwitcher/AppStore.swift Sources/CodexSwitcher/AppStore+SeamlessSwitch.swift Sources/CodexSwitcher/SwitchOrchestrator.swift Sources/CodexSwitcher/AutomationConfidenceCalculator.swift Sources/CodexSwitcher/Models.swift Tests/CodexSwitcherTests/SwitchOrchestratorTests.swift Tests/CodexSwitcherTests/AutomationConfidenceTests.swift Tests/CodexSwitcherTests/AppStoreSwitchCoordinatorTests.swift
git commit -m "feat: preflight switch decisions"
```

## Task 5: Surface Reliability Context In History UI

**Files:**
- Modify: `Sources/CodexSwitcher/MenuContentView+HistoryContent.swift`

- [ ] **Step 1: Add a compact decision section**

Show the most recent decision outcomes and blocked reasons in a way that fits the current history layout.

- [ ] **Step 2: Preserve existing timeline readability**

Do not turn history into a diagnostics dump. Prefer compact labels and short explanations.

- [ ] **Step 3: Manually verify the UI**

Run: `swift build`
Expected: PASS

Launch the app and confirm the history surface remains readable with the new reliability context.

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexSwitcher/MenuContentView+HistoryContent.swift
git commit -m "feat: show switch decision context in history"
```

## Task 6: Full Validation

**Files:**
- Modify: any touched files from previous tasks if fixes are needed

- [ ] **Step 1: Run the focused reliability suite**

Run: `swift test --filter Switch`
Expected: PASS

- [ ] **Step 2: Run the broader automation coverage**

Run: `swift test --filter Automation`
Expected: PASS

- [ ] **Step 3: Run the full suite**

Run: `swift test`
Expected: PASS

- [ ] **Step 4: Run a clean build**

Run: `swift build`
Expected: PASS

- [ ] **Step 5: Review the diff**

Run: `git --no-pager diff --stat HEAD~5..HEAD`
Expected: changed files align with Phase 1 scope only.

- [ ] **Step 6: Final commit if validation required follow-up changes**

```bash
git add <updated-files>
git commit -m "fix: polish switch reliability validation"
```

## Out of Scope For This Plan

- Diagnostics timeline correlation with `logs_2.sqlite`
- Thread graph and agent job intelligence from `state_5.sqlite`
- New power-user shortcuts and focus-mode UX
- Any export format expansion beyond the new decision record persistence
