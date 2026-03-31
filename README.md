# CodexSwitcher

A macOS menu bar app that manages multiple OpenAI Codex accounts and automatically switches between them when usage limits are reached — no manual login/logout needed.

![macOS](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Features

- **Auto-switching** — Detects rate limits from session logs and instantly switches to the best available account
- **Smart selection** — Picks the account with the lowest weekly usage %, not just round-robin
- **Real-time usage tracking** — Live session activity indicator and per-account token attribution
- **Cost tracking** — Per-account token usage and USD cost with model-specific pricing (matches CodexBar)
- **Model-aware pricing** — Accurate costs for gpt-4.x, gpt-5.x, o3, o4-mini with cached token discounts
- **Rate limit bars** — Weekly and 5-hour (Plus/Pro) rate limit progress bars per account
- **Rate limit forecasting** — Estimates time-to-exhaustion based on usage pace and historical patterns
- **Account health indicators** — Per-account status dots: 🟢 healthy, 🟡 stale token, ⚪ unchecked
- **Live session indicator** — Green pulse when Codex is actively using tokens
- **Exhaustion UX** — Clear banner when all accounts are rate-limited, with next-reset time and manual override
- **Restored notifications** — Get notified when a rate-limited account becomes available again
- **Lock icons** — Visual lock indicator on exhausted accounts
- **Auth recovery** — Automatic recovery if `~/.codex/auth.json` is corrupted or deleted
- **Switch verification** — Post-switch confirmation that the correct account is active, with automatic rollback on failure
- **In-app login** — Add accounts without Terminal popup; secure browser-based login flow
- **Email privacy** — One-click blur toggle to hide email addresses
- **Dark / Light mode** — Persistent appearance preference
- **TR / EN language** — Turkish and English UI support (auto-detects system language)
- **Account aliases** — Give each account a friendly name; rename anytime via right-click
- **Switch history** — Track all account switches with reasons and timestamps
- **Liquid glass UI** — Native macOS frosted-glass popover design
- **Zero dependencies** — Pure Swift, no external packages
- **CPU optimized** — File modification time caching to avoid re-parsing unchanged session files

---

## Requirements

- macOS 26 (Tahoe) or later
- [OpenAI Codex CLI](https://github.com/openai/codex) installed (`codex` accessible in `$PATH`)
- Xcode 16 / Swift 6.2 (for building from source)

---

## Installation

### Download (recommended)

1. Download `CodexSwitcher-vX.X.X.zip` from the [Releases](../../releases) page
2. Unzip and move `CodexSwitcher.app` to `/Applications`
3. Launch — the app appears in the menu bar

> **⚠️ macOS Gatekeeper Warning**
>
> Because CodexSwitcher is not notarized with an Apple Developer certificate, macOS may block it on first launch with a message like *"Apple could not verify…"* or *"app is damaged"*. This is expected for open-source apps distributed outside the App Store.
>
> **Fix — Option A (GUI):**
> 1. Click **Done** on the warning dialog
> 2. Open **System Settings → Privacy & Security**
> 3. Scroll down → click **Open Anyway**
>
> **Fix — Option B (Terminal, one command):**
> ```bash
> xattr -dr com.apple.quarantine /Applications/CodexSwitcher.app
> ```
> After either fix, the app opens normally and you won't be asked again.

### Build from source

```bash
git clone https://github.com/senoldogan/codex-switcher.git
cd codex-switcher
bash build.sh
open CodexSwitcher.app
```

To install permanently:

```bash
cp -R CodexSwitcher.app /Applications/
```

To launch at login: **System Settings → General → Login Items** → add `CodexSwitcher.app`.

---

## How It Works

```
~/.codex/auth.json          ← active account credentials (Codex reads this)
~/.codex/sessions/*.jsonl   ← session logs (CodexSwitcher monitors for rate limits)
~/.codex-switcher/profiles/ ← stored credentials per account
```

1. CodexSwitcher watches `~/.codex/sessions/` for rate-limit events (`429`, `rate_limit`, `quota_exceeded`)
2. On detection it atomically replaces `~/.codex/auth.json` with the best available account
3. Rate-limit data is fetched from the Codex API for all accounts on each popover open
4. After switching, the new auth is verified — if verification fails, automatic rollback occurs

---

## Adding Accounts

1. Click the menu bar icon → **Add Account** (`+`)
2. Browser opens automatically for sign-in (no Terminal popup)
3. Sign in with your account in the browser
4. CodexSwitcher detects the new credentials automatically
5. Optionally give the account an alias, then click **Save**

---

## Usage

| Action | How |
|--------|-----|
| Switch account | Click an account row |
| Force switch to next | Click **Switch Now** in the footer |
| Rename account | Right-click account row → **Rename** |
| Delete account | Right-click account row → **Delete** |
| Blur/show emails | Settings bar → 👁 icon |
| Toggle dark/light | Settings bar → 🌙/☀️ icon |
| Change language | Settings bar → 🌐 icon (cycles Auto → TR → EN) |
| View switch history | Click **History** in the footer |

### Health Indicators

Each account row shows a colored dot indicating auth health:

| Indicator | Meaning |
|-----------|---------|
| 🟢 Green | Healthy — API responding, auth valid |
| 🟡 Yellow | Stale — Token expired (401/403), re-login needed |
| ⚪ Gray | Unknown — Not yet checked or network error |
| 🔒 Red lock | Exhausted — Rate limit reached |

### Exhaustion State

When all accounts are rate-limited, a banner appears with:
- Which account resets next and when
- A **"Switch anyway"** button for manual override

---

## Changelog

### v1.5.0
- **Real-time session indicator** — Live green pulse on the active account when Codex is actively processing
- **Model-aware cost calculation** — Accurate pricing for gpt-4.x, gpt-5.x, o3, o4-mini including cached token discounts
- **Improved token attribution** — Sessions are correctly attributed to accounts based on switch history
- **Live usage updates** — Session file monitoring triggers immediate UI refresh when new tokens are detected
- **Bug fixes** — Account switching now properly updates both config and auth files

### v1.4.0
- Per-account token usage and cost tracking
- Rate limit forecasting with time-to-exhaustion estimates
- Restored notifications when rate limits reset
- In-app login flow without Terminal popup
- Switch verification with automatic rollback

### v1.3.0
- Smart account selection by weekly usage percentage
- Account health indicators (healthy, stale, unchecked)
- Exhaustion state with next-reset info
- Turkish and English language support

---

## Architecture

| File | Responsibility |
|------|---------------|
| `AppStore.swift` | Central state management, profile CRUD, smart switching, rate limit polling |
| `ProfileManager.swift` | Auth file management, verification, backup/rollback |
| `RateLimitFetcher.swift` | API polling for rate limit data |
| `RateLimitForecaster.swift` | Usage pace analysis and exhaustion prediction |
| `CostCalculator.swift` | USD cost calculation with model-specific pricing |
| `UsageMonitor.swift` | FSEvents-based session log watcher |
| `SessionTokenParser.swift` | Per-account token usage with model tracking and file caching |
| `MenuContentView.swift` | Popover UI with inline navigation |
| `AddAccountInlineView.swift` | Inline account addition with browser-based login |
| `L10n.swift` | TR/EN localization system |

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
