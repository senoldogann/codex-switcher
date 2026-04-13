# Phase 2 Diagnostics And Forensics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the first diagnostics and forensics slice so CodexSwitcher can explain recent operational behavior through one bounded, privacy-safe diagnostics timeline.

**Architecture:** Reuse existing local records instead of introducing SQLite correlation immediately. Build a diagnostics layer from switch decisions, switch timeline events, reconciliation anomalies, alerts, and data-quality signals; expose it in `AnalyticsSnapshot`, analytics export, and the analytics window.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftUI, Foundation, AppKit

---

## Scope

Phase 2 slice 1 includes:

- typed diagnostics timeline models
- timeline building from already trusted local sources
- diagnostics summary counts
- privacy-bounded diagnostics export in JSON
- diagnostics panel in the analytics window

Out of scope for this slice:

- `logs_2.sqlite` ingestion
- `state_5.sqlite` correlation
- thread graph features
- raw prompt or local path export
