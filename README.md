# Omarchy AI Subscription Usage — Improved 󱚣

An enhanced, user-owned replacement for the stock [Omarchy Linux](https://omarchy.org/) AI Subscription Usage bar widget (`omarchy.agents`) that survives system updates and fixes token expiration issues.

---

## What This Adds & Fixes

- 🚀 **Antigravity CLI (`agy`) Tab**: Full token statistics (7-day daily token chart + complete per-model input/output/cache breakdown parsed from SQLite WAL/protobufs) and live Google AI account quota windows (`loadCodeAssist` / `retrieveUserQuotaSummary`).
- 🔐 **Keyring-Aware Antigravity OAuth Renewal**: Reads `agy`'s live OAuth token from the Freedesktop Secret Service keyring (`secret-tool lookup service gemini username antigravity`, with fallback to the legacy token file) and automatically refreshes expired tokens via `agy models`.
- 🔄 **Automatic Claude Code OAuth Renewal**: Detects when `~/.claude/.credentials.json` has an expired `accessToken` alongside a valid `refreshToken` and silently runs `claude auth status` before collection—eliminating false *"Sign-in expired"* warnings when you haven't opened `claude` recently.
- 󰑐 **In-Panel Refresh Button**: Adds a clickable `󰑐` refresh button directly in the panel header (in addition to the `R` / `Enter` keyboard shortcuts and `omarchy-shell omarchy.agents refresh` CLI command).
- 👤 **100% User-Agnostic & Customizable**: Works for any Linux username (`<user>.agents`), auto-detects installed CLIs, and supports interactive or flag-driven setup for provider toggles, refresh intervals, and multi-device usage sync.
- 🤖 **AI Agent Skill Included (`SKILL.md`)**: Ready for Antigravity CLI, Claude Code, Codex, or Cursor to install, configure, and maintain autonomously after interviewing the user for their preferences.

---

## Quick Start (Interactive Installer)

Clone the repository and run the installer:

```bash
git clone https://github.com/max38tech/omarchy-ai-usage-improved.git
cd omarchy-ai-usage-improved
./install.sh
```

The installer will:
1. Ask for your preferred plugin namespace (defaults to `<your-username>.agents`), which AI providers to enable (`antigravity`, `claude`, `codex`, `fireworks`), refresh interval, and optional multi-device sync folder.
2. Verify system dependencies (`python3`, `jq`, `libsecret` / `secret-tool`).
3. Install the plugin to `~/.config/omarchy/plugins/<user>.agents`.
4. Back up `~/.config/omarchy/shell.json` and swap `omarchy.agents` $\rightarrow$ `<user>.agents`.
5. Optionally install `SKILL.md` to `~/.agents/skills/omarchy-ai-usage/SKILL.md`.
6. Run an initial usage & quota collection and hot-reload `omarchy-shell`.

### Non-Interactive / Scripted Installation

```bash
./install.sh \
  --user "$(whoami)" \
  --refresh-interval 900 \
  --enable-antigravity true \
  --enable-claude true \
  --enable-codex true \
  --enable-fireworks false \
  --sync-mode Off \
  --bar-section right \
  --install-skill true \
  --non-interactive
```

---

## AI Agent Installation (`SKILL.md`)

If you use an AI coding assistant (Antigravity CLI, Claude Code, Codex, Cursor):

1. Copy `SKILL.md` to your agent skills directory:
   ```bash
   mkdir -p ~/.agents/skills/omarchy-ai-usage
   cp SKILL.md ~/.agents/skills/omarchy-ai-usage/SKILL.md
   ```
2. Prompt your agent:
   > *"Use the omarchy-ai-usage skill to install the improved AI subscription usage panel on my system."*
3. The agent will ask you which providers and settings you want and set everything up automatically.

---

## Controls & CLI Commands

| Action | Shortcut / Command |
| :--- | :--- |
| **Open / Close Panel** | Left-click `󱚣` in the top bar |
| **Switch Provider Tab** | Middle-click `󱚣`, click provider tabs, or press `←` / `→` |
| **Force Refresh All Limits & Usage** | Click `󰑐` in the panel header, or press `R` / `Enter` |
| **Launch Active Agent** | Right-click `󱚣` (launches `agy` when on Antigravity tab, or `omarchy-agent --pick`) |
| **Refresh via CLI** | `omarchy-shell omarchy.agents refresh` |
| **Run Collector Manually** | `~/.config/omarchy/plugins/$(whoami).agents/update-usage --force` |

---

## Uninstallation

To remove the custom plugin and restore stock `omarchy.agents`:

```bash
./uninstall.sh
```

---

## License

MIT
