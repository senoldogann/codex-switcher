# CodexSwitcher

A macOS menu bar app that manages multiple OpenAI Codex accounts and automatically switches between them when usage limits are reached — no manual login/logout needed.

![macOS](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Features

- **Auto-switching** — Detects rate limits from session logs and instantly switches to the best available account
- **Smart selection** — Picks the account with the lowest weekly usage %, not just round-robin
- **Real-time usage** — Shows weekly and 5-hour (Plus/Pro) rate limit bars per account
- **Email privacy** — One-click blur toggle to hide email addresses
- **Dark / Light mode** — Persistent appearance preference
- **TR / EN language** — Turkish and English UI support (auto-detects system language)
- **Account aliases** — Give each account a friendly name; rename anytime via right-click
- **Liquid glass UI** — Native macOS frosted-glass popover design
- **Zero dependencies** — Pure Swift, no external packages

---

## Requirements

- macOS 26 (Tahoe) or later
- [OpenAI Codex CLI](https://github.com/openai/codex) installed (`codex` accessible in `$PATH`)
- Xcode 16 / Swift 6.2 (for building from source)

---

## Installation

### Download (recommended)

Download the latest `.app` from the [Releases](../../releases) page and move it to `/Applications`.

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

---

## Adding Accounts

1. Click the menu bar icon → **Add Account** (`+`)
2. A Terminal window opens and runs `codex login`
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
