# Seamless Switch And Reliability Design

Date: 2026-04-03
Project: CodexSwitcher
Status: Approved in chat, pending written spec review

## Goal

Improve CodexSwitcher in four linked areas without changing the established visual language:

1. Fix current UX regressions:
   - `Add Account > Start` does not reliably begin login
   - `Projects > CSV` does not reliably export
   - top and bottom layout spacing wastes vertical space
   - history tab bar is too cramped
2. Make account switching happen at the correct boundary instead of immediately in the middle of active work.
3. Prefer restart-free switching so the current Codex process does not need to be closed and relaunched for the next request.
4. Expose stronger analytics and reliability signals so the app becomes closer to "set and forget".

## Non-Goals

- No visual redesign or new color system
- No attempt to continue an already-running Codex request under a different account
- No Sparkle or external updater migration
- No broad refactor unrelated to switching, analytics, or the current UI regressions

## Product Direction

The target behavior is pragmatic:

- If a limit is reached during active work, CodexSwitcher should not interrupt the current task.
- The switch should be prepared while the task is running, then applied at the next safe boundary.
- The next request should use the new account without forcing a restart when possible.
- Restart becomes a fallback, not the default path.

## Phase 1: Bug And Layout Stabilization

### Scope

Fix the current issues that block trust in the UI:

- `Add Account > Start` must always trigger the login process or show a clear failure state.
- `Projects > CSV` must always open a save flow and write a valid CSV.
- The account list should start higher and use more of the available vertical space.
- The bottom status strip should remain present but consume less height.
- The history tab bar should fit the available width cleanly without looking compressed.

### Files

- `Sources/CodexSwitcher/AppStore.swift`
- `Sources/CodexSwitcher/AddAccountInlineView.swift`
- `Sources/CodexSwitcher/MenuContentView.swift`
- `Sources/CodexSwitcher/ProjectBreakdownView.swift`
- `Sources/CodexSwitcher/ProjectCSVExporter.swift`

### Expected Result

The app returns to a stable baseline before switch orchestration changes begin.

## Phase 2: Safe Switch Boundary

### Problem

Current switching behavior is tied too closely to rate-limit detection. This risks switching at the wrong moment and forces the process model to be aggressive.

### Design

Introduce a switch state machine:

- `idle`
- `pendingSwitch`
- `readyToSwitch`
- `verifying`

When a limit event is detected:

1. Determine whether active work is still in progress.
2. If active work exists, do not switch immediately.
3. Record a pending switch request with reason, target account, and timestamp.
4. Monitor for a safe boundary:
   - token activity settles
   - current turn ends
   - a new request boundary is observed
5. Apply the switch only after that boundary is reached.

### Signals

Safe boundary detection can draw from:

- session JSONL activity cadence
- latest token event timing
- task lifecycle markers already parsed from the session logs
- existing active-turn tracking in `AppStore`

### Files

- `Sources/CodexSwitcher/AppStore.swift`
- `Sources/CodexSwitcher/SessionTokenParser.swift`
- `Sources/CodexSwitcher/UsageMonitor.swift`
- `Sources/CodexSwitcher/Models.swift`

## Phase 3: Seamless Switch With Fallback

### Goal

Remove restart as the primary switching mechanism.

### Design

After a safe boundary is reached:

1. Atomically rotate `~/.codex/auth.json` to the target account.
2. Leave the Codex process running.
3. Observe the next request and verify whether the new account is actually being used.
4. If verification succeeds:
   - mark the switch successful
   - remain restart-free
5. If verification fails:
   - run the current restart path as controlled fallback
   - record the fallback reason

### Constraints

- The design assumes the current request is allowed to finish.
- The design does not assume Codex will hot-reload auth on every request; it verifies observed behavior.
- If verification is inconclusive, the system should prefer safety over optimism.

### Files

- `Sources/CodexSwitcher/AppStore.swift`
- `Sources/CodexSwitcher/ProfileManager.swift`
- small helper types if needed for switch verification and state transitions

## Phase 4: Deep Analytics And Reliability

### Switch Timeline

Add structured switch analytics for power users:

- switch reason
- pending duration
- switch execution time
- seamless success or failure
- fallback restart triggered or not

### Account Reliability

Track per-account behavior:

- critical limit frequency
- stale auth frequency
- successful seamless switch count
- verification failure count
- fallback restart count

### Automation Confidence

Expose operational health:

- watcher freshness
- last successful rate-limit fetch
- last failed fetch
- pending switch age
- last successful seamless switch time

### UI Strategy

Do not introduce a new visual system. Add this data as:

- compact summaries in existing views
- additional lightweight analytics subsections
- existing typography and material styling

### Files

- `Sources/CodexSwitcher/Models.swift`
- `Sources/CodexSwitcher/AppStore.swift`
- `Sources/CodexSwitcher/MenuContentView.swift`
- new lightweight analytics views if needed

## State Model

New data likely needed:

- switch orchestration state
- pending switch metadata
- last seamless switch result
- verification result details
- reliability counters and timestamps

These should be represented as focused model types instead of adding more ad hoc booleans to `AppStore`.

## Error Handling

- Login start failure must become explicit in the UI.
- Save/export failure must provide visible feedback.
- Seamless verification must distinguish:
  - success
  - explicit failure
  - inconclusive state
- Fallback restart must be recorded, not hidden.

## Testing Plan

### Phase 1

- login start path launches the process
- CSV export builder produces valid escaped output
- layout changes compile and preserve current navigation behavior

### Phase 2

- active work keeps switch in `pendingSwitch`
- safe boundary advances pending switch to execution
- no premature switch while token activity is still active

### Phase 3

- successful verification avoids restart
- failed verification triggers restart fallback
- switch history records seamless vs fallback outcomes

### Phase 4

- switch timeline aggregates correctly
- reliability counters update correctly
- health summaries reflect fetch and switch state accurately

## Implementation Order

1. Phase 1: current bugs and spacing issues
2. Phase 2: safe switch boundary
3. Phase 3: seamless switch with fallback
4. Phase 4: analytics and reliability surfaces

## Risks

1. Codex may cache auth more aggressively than expected.
   Mitigation: verification-first design with restart fallback.

2. Safe boundary detection may be too eager or too conservative.
   Mitigation: state-machine logging and threshold tuning based on observed session traces.

3. `AppStore` may become too large.
   Mitigation: move new switch and reliability models into focused helper types early.

## Success Criteria

- Add Account login can be started reliably from the app
- CSV export works reliably from the Projects tab
- Main layout uses vertical space more efficiently without redesign
- Switches happen at safer request boundaries
- Restart is no longer the default switch path
- Reliability and switch behavior become observable in-app
