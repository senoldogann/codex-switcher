# CodexSwitcher

A macOS menu bar app that manages multiple OpenAI Codex and Claude Code accounts, automatically switches between them when usage limits are reached, and gives you deep analytics on your AI coding sessions.

![macOS](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/license-MIT-green)

<p align="center">
  <img src="assets/screenshot.png" width="320" alt="CodexSwitcher showing multiple accounts with weekly/5-hour rate limit bars, token usage, cost, and the active account indicator">
</p>

---

## Features

### Account Management
- **Auto-switching** — Detects rate limits via API and switches to the best available account automatically
- **Smart selection** — Picks the account with the lowest weekly usage %, not round-robin
- **Multi-AI support** — Manage both **OpenAI Codex** and **Claude Code** accounts side by side
- **Codex auto-restart** — Force-quits and relaunches Codex after every switch (no manual exit needed)
- **Switch verification** — Post-switch confirmation with automatic rollback on failure
- **Re-login flow** — Refresh stale tokens without leaving the app
- **Account aliases** — Friendly names per account, rename via right-click
- **Auth recovery** — Automatic recovery if `~/.codex/auth.json` is corrupted

### Token & Cost Tracking
- **Per-event token attribution** — Accurate per-account tracking using delta computation from JSONL session files
- **Real input/output split** — Cost calculation uses actual `input_tokens`/`output_tokens` from session logs (not a rough approximation)
- **Cost tracking** — Per-account USD cost with model-specific pricing for gpt-4.x, gpt-5.x, o3, o4-mini
- **Rate limit bars** — Weekly and 5-hour remaining progress bars per account
- **Rate limit forecasting** — Estimates time-to-exhaustion based on usage pace
- **80% warning** — Notification when an account approaches its weekly limit
- **Restored notifications** — Get notified when a limited account becomes available again
- **Weekly budget alerts** — Set a USD budget; receive a notification when you exceed it
- **Weekly summary** — Automatic Sunday evening stats notification

### Codex Insights (Analytics)
- **Projects** — All-time per-project token and cost breakdown with progress bars; drill down into sessions per project; CSV export
- **Sessions** — Full session list with search, parent/child threading, agent role badges (reviewer, explorer, worker)
- **Heatmap** — 7-day × 24-hour activity heatmap showing when you code most
- **Top $** — Top 20 most expensive prompts ranked by token count
- **Chart** — 7-day daily token usage chart per account

### UI & UX
- **Account health indicators** — 🟢 healthy · 🟡 stale token · ⚪ unchecked · 🔒 exhausted
- **Live session indicator** — Green pulse when tokens are actively being consumed
- **Switch history** — Full log with type icons: ⚡ auto-switch · ↔ manual switch
- **Email privacy** — One-click blur toggle for email addresses
- **Dark / Light mode** — Persistent appearance preference
- **TR / EN language** — Turkish and English UI (auto-detects system language)
- **Update checker** — GitHub-based update notifications (no Sparkle dependency)

---

## Requirements

- macOS 26 (Tahoe) or later
- [OpenAI Codex CLI](https://github.com/openai/codex) installed (for Codex accounts)
- [Claude Code CLI](https://github.com/anthropics/claude-code) installed (for Claude accounts)

---

## Installation

1. Download `CodexSwitcher-vX.X.X-signed.zip` from the [Releases](../../releases) page
2. Unzip and move `CodexSwitcher.app` to `/Applications`
3. Launch — the app appears in the menu bar

> Signed with a Developer ID certificate and notarized by Apple. No Gatekeeper warning on first launch.

To launch at login: **System Settings → General → Login Items** → add `CodexSwitcher`.

---

## How It Works

```
~/.codex/auth.json              ← active Codex credentials (Codex reads this)
~/.codex/sessions/**/*.jsonl    ← session logs (token usage, prompts, models)
~/.codex-switcher/profiles/     ← stored credentials per account
~/.codex-switcher/cache/        ← token delta cache for fast attribution
```

1. CodexSwitcher watches `~/.codex/sessions/` for rate-limit signals
2. On detection it calls the rate-limit API to **confirm** the limit is actually reached (no false positives)
3. If confirmed, it atomically replaces `~/.codex/auth.json` with the best available account
4. Codex is force-quit and relaunched so it picks up the new credentials
5. The switch is verified — if verification fails, automatic rollback occurs

Token attribution reads `input_tokens`, `cached_input_tokens`, and `output_tokens` from each session's JSONL events and maps them to the account that was active at that timestamp.

---

## Adding Accounts

### Codex
1. Click **+ Add Account** → select **Codex**
2. Browser opens automatically for OAuth sign-in
3. Sign in — CodexSwitcher detects the new credentials automatically
4. Give the account an alias → click **Save**

### Claude Code
1. Click **+ Add Account** → select **Claude Code**
2. Terminal opens and runs `claude auth login`
3. Complete the browser OAuth flow
4. CodexSwitcher detects the Keychain update automatically
5. Give the account an alias → click **Save**

---

## Usage

| Action | How |
|--------|-----|
| Switch account | Click an account row |
| Force switch to next | **Switch Now** in the footer |
| View switch history | **History** tab |
| View analytics | **Chart / Projects / Sess. / Heatmap / Top $** tabs |
| Rename account | Right-click → **Rename** |
| Delete account | Right-click → **Delete** |
| Re-login stale account | Right-click → **Re-login** |
| Set weekly budget | Settings bar → **$X/$Y** button |
| Reset token statistics | Settings bar → **↺** (with confirmation) |
| Blur/show emails | Settings bar → **Show/Hide** |
| Toggle dark/light | Settings bar → **Dark/Light** |
| Change language | Settings bar → **🌐** (Auto → TR → EN) |
| Check for updates | Footer → **Update** (opens GitHub releases page) |

---

## Changelog

### v1.14.0
- **Multi-AI support** — Add and manage Claude Code accounts alongside Codex accounts; credentials stored in Keychain
- **Codex Insights** — 5 analytics tabs: Projects (drill-down + CSV export), Sessions (search + threading), Heatmap, Top $, Chart
- **Weekly budget alerts** — Set a USD spend limit and get notified when you exceed it
- **Weekly summary** — Automatic Sunday evening token/cost stats notification
- **Accurate cost calculation** — Uses real input/output token split from JSONL instead of a 50/50 approximation (was overestimating by ~3×)
- **Reset button fixed** — Confirmation dialog added; all 4 cache files cleared; all Insights views reset; UI refreshes immediately
- **Update checker** — GitHub API-based; Sparkle removed (was blocked by Gatekeeper on macOS 26)
- **Claude login path** — Uses `zsh -l` (login shell) to resolve `claude` binary in `~/.local/bin`, `/opt/homebrew/bin`, etc.
- **Update button** — Always opens releases page when clicked (previously silent when already up to date)

### v1.9.1
- **Codex force-quit** — Switched from `terminate()` to `forceTerminate()` (SIGKILL); eliminates the "Quit Codex?" dialog
- **App icon fix** — Icon now correctly appears in Dock and Finder

### v1.9.0
- **Codex auto-restart** — Codex is automatically closed and relaunched after every account switch
- **History icons** — Switch history shows ⚡ (auto) or ↔ (manual) icons
- **Signed & notarized** — Developer ID signed and Apple notarized; no Gatekeeper warning

### v1.8.2
- **API-verified auto-switch** — Confirms rate limit via API before switching; eliminates false positives

### v1.8.1
- **Window-aware baseline** — Long-running sessions no longer produce token spikes at the 7-day boundary
- **No-history attribution** — Tokens from before any switch history are dropped rather than misattributed

### v1.8.0
- **Per-event delta attribution** — Complete rewrite of token parser; eliminates billions of misattributed tokens

### v1.7.0
- **Energy optimization** — Polling interval 60s → 300s; file descriptor leak fixed
- **Reset statistics** — Clear all token/cost/forecast data
- **Re-login flow** — Refresh expired tokens without leaving the app
- **80% limit warning** — Notification when weekly usage crosses 80%

---

## Architecture

| File | Responsibility |
|------|---------------|
| `AppStore.swift` | Central state, profile CRUD, smart switching, rate limit polling, AI restart |
| `ProfileManager.swift` | Auth file + Keychain management, verification, backup/rollback |
| `ClaudeCodeManager.swift` | Keychain read/write for Claude Code credentials |
| `SessionTokenParser.swift` | Per-event delta attribution, Insights calculation (projects/sessions/heatmap) |
| `RateLimitFetcher.swift` | API polling for rate limit data |
| `RateLimitForecaster.swift` | Usage pace analysis and exhaustion prediction |
| `CostCalculator.swift` | USD cost calculation with model-specific pricing |
| `UsageMonitor.swift` | FSEvents-based session log watcher |
| `UpdateChecker.swift` | GitHub API update checker |
| `MenuContentView.swift` | Popover UI with tab navigation |
| `ProjectBreakdownView.swift` | Projects analytics tab with drill-down and CSV export |
| `SessionExplorerView.swift` | Sessions tab with search and thread tree |
| `HeatmapView.swift` | 7×24 activity heatmap |
| `ExpensivePromptsView.swift` | Top 20 most expensive prompts |
| `UsageChartView.swift` | 7-day daily usage chart |
| `BundleExtension.swift` | Bundle.appResources — correct icon/resource lookup in signed .app |
| `L10n.swift` | TR/EN localization |

---

## Contributing

Pull requests are welcome. Please open an issue first for major changes.

1. Fork the repo
2. Create a branch: `git checkout -b feature/your-feature`
3. Commit: `git commit -m 'feat: add your feature'`
4. Push: `git push origin feature/your-feature`
5. Open a Pull Request

---

## License

MIT — see [LICENSE](LICENSE)

---

## Author

**Senol Dogan** — Senior Full Stack Developer

- Website: [senoldogan.dev](https://www.senoldogan.dev)
- Email: [contact@senoldogan.dev](mailto:contact@senoldogan.dev)
- LinkedIn: [linkedin.com/in/senoldogann](https://www.linkedin.com/in/senoldogann)
- X / Twitter: [@senoldoganx](https://x.com/senoldoganx)
