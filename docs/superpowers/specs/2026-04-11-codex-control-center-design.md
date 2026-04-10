# Codex Control Center Design

**Date:** 2026-04-11
**Product:** CodexSwitcher
**Status:** Draft for review

## Goal

Evolve CodexSwitcher from a reliable account switcher with analytics into a broader local control center for Codex Desktop. The product should manage account continuity, explain runtime behavior, surface thread and agent execution patterns, and accelerate daily use without compromising trust, safety, or clarity.

## Problem Statement

CodexSwitcher already solves an important operational problem: moving between accounts when rate limits become restrictive and giving the user visibility into token and cost usage from local session logs. However, the local Codex installation exposes a richer runtime surface that the app does not yet use:

- `~/.codex/auth.json` for active credentials
- `~/.codex/sessions/**/*.jsonl` for prompts, token usage, and session metadata
- `~/.codex/state_5.sqlite` for threads, jobs, agent jobs, spawn edges, and repo metadata
- `~/.codex/logs_2.sqlite` for runtime logs and structured failures

Today, these sources are only partially connected. The result is a product that is strong in account switching and basic analytics, but still weak in four higher-value areas:

1. Reliability orchestration around switching
2. Deep diagnostics and forensics
3. Thread and agent workflow intelligence
4. Power-user ergonomics for daily operation

## Product Direction

Build the next stage of the app as a four-phase program. Each phase must ship as a complete, user-visible improvement and must reuse the same local-first architecture. New capabilities should remain explainable, deterministic where possible, and audit-friendly.

## Non-Goals

- No cloud backend
- No remote telemetry service
- No mutation of Codex internal SQLite state
- No invasive coupling to private Codex internals beyond local read-only inspection
- No speculative features that cannot be grounded in local artifacts already present on disk

## User Outcomes

After the full program lands, the user should be able to:

- Trust that switching decisions are safe, deliberate, and reversible
- Understand why a switch happened, failed, or was delayed
- Inspect how Codex threads, agents, jobs, and repos behave over time
- Spot runaway usage, anomalous workflows, and reliability degradation early
- Operate daily with less friction through smarter shortcuts and context-aware UI

## Existing Strengths To Preserve

The current app already has a strong base that should stay intact:

- Auto-switching with proactive thresholds
- Token and cost attribution from session JSONL
- Reconciliation ledger and audit export
- Session explorer with thread depth and agent role badges
- Analytics window with summary, trends, projects, sessions, heatmap, and top-cost views
- Reliability timeline and automation confidence concepts

The new work should extend these strengths instead of replacing them.

## Design Principles

### 1. Local-First, Read-Only Intelligence

CodexSwitcher may read from Codex-managed files and databases, but should avoid mutating Codex state except for the already-established account activation path through `auth.json`.

### 2. One Data Source, Many Views

Each local source should be normalized once into internal domain models, then reused across reliability, analytics, and UX layers. Avoid parallel parsers or duplicated view-specific logic.

### 3. Explainability Over Magic

Every important decision should have a visible reason:

- why a profile was selected
- why a switch was blocked
- why a switch retried or rolled back
- why an anomaly was raised
- why a job or thread is considered risky or expensive

### 4. Graceful Degradation

If a Codex file is missing or a schema changes, the app should narrow functionality and mark the affected view as partial, rather than producing silent misinformation.

### 5. Phase Independence

Each phase must be shippable on its own, without requiring the later phases to justify the architecture.

### 6. Performance Tiering

The app is a menu bar utility first. Lightweight status rendering must not depend on heavyweight diagnostics or graph ingestion. New architecture must preserve fast startup, predictable refresh behavior, and cancellable background work.

## Architecture Overview

The expanded product should be organized into four layers:

1. **Collectors**
   Read local Codex artifacts and convert them into typed records.

2. **Domain Engines**
   Compute derived state such as reliability scores, anomaly reports, thread graphs, and workflow summaries.

3. **Snapshots**
   Produce UI-ready snapshots at different cost tiers for the menu bar, analytics window, and future diagnostics views.

4. **Presentation**
   Render focused views with consistent language around confidence, health, evidence, and actionability.

This continues the current direction already visible in the analytics snapshot architecture and should be extended rather than replaced.

## Snapshot Strategy

The product should keep one normalized domain layer, but should not force every UI surface through one heavyweight snapshot.

Required snapshot tiers:

- `MenuSnapshot`
  - lightweight
  - fast to compute
  - refreshes on a tight cadence
  - limited to active profile state, readiness, session activity, and compact alerts
- `AnalyticsSnapshot`
  - medium weight
  - refreshes less often or on explicit interaction
  - powers cost, usage, reconciliation, and higher-level summaries
- `DiagnosticsSnapshot`
  - heavy and on-demand
  - only built when a diagnostics or thread-intelligence surface is visible
  - supports cancellation, partial loading, cursor-based progression, and stale-data indicators

Shared rules:

- collectors feed one normalized domain layer
- snapshots compose from normalized records instead of hitting disk directly
- long-running refresh work must happen off the menu-rendering path
- each snapshot tier must define refresh cadence, cancellation behavior, and cache lifetime
- startup must prefer a fast cached snapshot over blocking on deep recomputation

## Data Sources

### Session JSONL

Purpose:

- token attribution
- prompt and turn analytics
- active session boundaries
- model usage
- project and prompt summaries

Future additions:

- richer session risk markers
- switch preflight context
- prompt-cost concentration analysis

### `state_5.sqlite`

Purpose:

- thread inventory
- parent/child thread relationships
- job and agent job state
- branch and repo metadata
- model and provider metadata

Future additions:

- thread graph visualization
- stuck job detection
- spawn-depth diagnostics
- per-repo and per-branch workflow analytics

### `logs_2.sqlite`

Purpose:

- runtime failure context
- log-level summaries
- time-aligned diagnostics around switch events or runaway sessions

Future additions:

- fallback clustering
- crash and warning correlation
- “what changed before degradation” diagnostics

## Phase Plan

## Phase 1: Automatic Switching + Reliability

### Objective

Turn switching into an explainable orchestration system instead of a thin action pipeline.

### Core additions

- Switch preflight checks before every activation attempt
- Profile readiness scoring from rate limit health, auth freshness, recent failures, and availability
- Structured switch decision record with evidence and rejection reasons
- Visible pending queue lifecycle with timestamps and wait reasons
- Rollback or safe halt path when activation or verification fails repeatedly
- Reliability scorecard that summarizes per-profile and global automation health

### User-facing results

- Users can see not only what happened, but why the app chose that path
- Bad targets are skipped with explicit reasons
- Repeated failures become diagnosable instead of mysterious
- Manual overrides remain available but safer

### Technical shape

Add a dedicated reliability domain around switching rather than continuing to grow `AppStore` directly. The orchestration result should be represented as typed records that can feed both history and diagnostics views.

### Phase 1 boundary

Phase 1 should stay grounded in existing inputs already trusted by the product:

- auth state
- rate-limit fetch state
- session activity state
- local switch history and timeline

Phase 1 may introduce a minimal evidence and event record model for switch decisions, queue transitions, verification outcomes, and rollback reasons. It should not depend on cross-source log correlation from `logs_2.sqlite` or workflow correlation from `state_5.sqlite`. Those remain Phase 2 and Phase 3 work.

## Phase 2: Deep Analytics + Forensics

### Objective

Expand from usage analytics into operational forensics.

### Core additions

- Unified diagnostics timeline that joins rate-limit changes, switch events, session activity, and runtime logs
- Cost and usage analytics grouped by repo, branch, model, thread source, and time window
- Anomaly engine for unexplained token spikes, idle drain, repeated fallback loops, and noisy jobs
- Exportable forensic bundle for postmortem review
- Confidence markers for every anomaly and diagnostic claim

### User-facing results

- Users can answer “what happened here?” without digging through raw files
- Cost spikes and suspicious drain patterns become searchable and explainable
- Reliability issues can be tied to concrete evidence rather than intuition

### Technical shape

Introduce normalized diagnostics records shared by analytics and reliability. This work should reuse existing reconciliation concepts and extend them to non-rate-limit evidence.

## Phase 3: Codex Thread / Agent / Workflow Intelligence

### Objective

Expose how Codex actually works over time at the thread, job, and agent level.

### Core additions

- Thread graph view backed by `threads` and `thread_spawn_edges`
- Agent execution summaries from `agent_jobs` and `agent_job_items`
- Workflow metrics by repo, branch, role, model, and spawn depth
- Detection of risky workflow patterns such as runaway workers, excessive branching, or stuck jobs
- Thread detail drilldown with parent chain, child tree, timing, and cost overlays

### User-facing results

- Users can identify which workflows are productive and which are wasteful
- The app becomes useful not just for account switching, but for understanding Codex work habits
- Team-style multi-agent patterns become inspectable from a local desktop app

### Technical shape

This phase needs a separate thread/workflow ingestion and derivation path. It should remain read-only and schema-tolerant. Any feature relying on uncertain SQLite schema details should carry a guarded capability flag.

### Phase 3 v1 limits

To keep the first thread/workflow release bounded:

- require repo and time-range filters before rendering heavy views
- cap graph rendering to a fixed node and edge budget
- show summary cards instead of a graph when limits are exceeded
- represent missing parents, duplicate edges, and incomplete joins explicitly in the UI
- allow cost overlays only when correlation confidence reaches an explicit threshold

## Phase 4: Daily UX + Power-User Features

### Objective

Reduce friction for frequent users and make the app feel operationally central.

### Core additions

- Keyboard-first quick actions
- Pinned profiles, repos, and favorite analytics views
- Compact and expanded menu bar summaries
- Context-aware notification throttling and focus mode
- “Recommended next action” hints driven by the reliability and diagnostics layers
- Faster drilldown flows from menu bar to analytics and thread detail

### User-facing results

- Less time spent navigating the app
- Faster access to the most relevant controls
- A more opinionated and useful daily workflow assistant

### Technical shape

This phase should consume outputs from the first three phases rather than inventing new data pipelines.

## Required Shared Infrastructure

The four phases should share a small set of core infrastructure investments:

### Typed Local Runtime Models

Create explicit models for:

- thread metadata
- job metadata
- agent job summaries
- runtime log records
- switch decision records
- diagnostics events

These models should be version-tolerant and fail clearly when required fields are unavailable.

### SQLite Adapter Safety

All SQLite-based collectors must follow strict adapter rules:

- open databases in read-only mode
- tolerate concurrent writers and WAL-backed databases
- detect table and column availability before queries run
- compute schema fingerprints for supported structures
- disable unsupported capabilities when required fields drift
- fail closed for user-facing claims when correlation confidence is too weak

Validation requirements:

- keep fixture databases sampled from real local Codex data
- add regression coverage for supported schema fingerprints
- surface partial-capability states in the UI instead of silently downgrading evidence

### Capability Detection

The app should detect which Codex artifacts are present and which features can safely run:

- session analytics available
- thread intelligence available
- log correlation available
- diagnostics partial

This allows future Codex app changes without catastrophic UI failure.

### Snapshot Composition

Derived views should be composed from one central snapshot flow rather than each view reading disk independently.

This means one normalized domain layer, not one monolithic UI snapshot.

### Confidence and Evidence Language

All new UI surfaces should use consistent wording such as:

- confirmed
- likely
- weak evidence
- unavailable
- not enough local data

## Data Classification and Privacy

New diagnostics and export features must preserve the current trust boundary of the product.

Default policy:

- redact prompt text
- redact raw local repo paths
- redact auth identifiers and account secrets
- redact raw runtime log payloads unless the user explicitly opts in

Export rules:

- standard exports remain privacy-bounded by default
- richer forensic bundles require explicit user opt-in
- export UI must preview which sensitive classes are included
- retention expectations should be visible before export completes
- later imports or share flows must assume exported bundles can leave the local machine

## Risks

### Codex Schema Drift

`state_5.sqlite` and `logs_2.sqlite` are local implementation details of Codex and may evolve. We must isolate parsing behind small adapters and capability checks.

### UI Overload

The app already has significant surface area. New views must be staged carefully to avoid turning the interface into a diagnostics dump.

### False Precision

Analytics and forensics can overstate certainty if evidence is partial. Confidence scoring and plain language are mandatory.

### AppStore Growth

The current `AppStore` is already broad. New work should extract domain logic into focused units instead of expanding it indefinitely.

## Success Metrics

Each phase should be evaluated by product-level outcomes, not just code completion.

### Phase 1

- lower repeated failed switch cycles
- clearer switch reason visibility
- lower manual recovery frequency

### Phase 2

- faster root-cause diagnosis of anomalies
- more trustworthy audit exports
- fewer “unknown” usage events in user-visible diagnostics

### Phase 3

- actionable insight into thread and agent behavior
- clear detection of stuck or wasteful workflows
- higher user understanding of repo and branch cost patterns

### Phase 4

- fewer clicks for common operations
- faster access to frequently used diagnostics
- better daily usability without adding clutter

## Recommended Delivery Order

Ship in this order:

1. Reliability orchestration
2. Diagnostics and forensics
3. Thread and workflow intelligence
4. Power-user UX

This order is recommended because:

- reliability is the operational core of the product
- diagnostics explain and justify reliability behavior
- thread intelligence benefits from diagnostics infrastructure
- UX features are strongest when powered by the first three layers

## Initial Implementation Boundary

The first implementation plan should cover only Phase 1. It should avoid partial work on later phases unless a shared primitive is required immediately for the reliability architecture.

## Open Questions To Resolve During Planning

- how much of the new reliability state belongs in persisted history versus ephemeral diagnostics
- whether a dedicated diagnostics window should remain separate from the main analytics window or extend it
- how to version capability detection when Codex local schema changes
- how much branch and repo intelligence should appear in the menu bar versus deeper windows

## Recommendation

Proceed with a Phase 1 implementation plan that introduces a dedicated reliability domain, explicit switch decision records, readiness scoring, and user-visible orchestration diagnostics without changing the fundamental local-first architecture.
