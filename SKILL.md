---
name: omarchy-ai-usage
description: >
  Install, configure, customize, and troubleshoot the improved Omarchy AI Subscription Usage
  bar widget and panel (`<user>.agents`). Adds Antigravity CLI (`agy`) token & quota tracking,
  automatic OAuth token renewal for Antigravity (via system keyring) and Claude Code
  (via `claude auth status`), and an in-panel clickable refresh button alongside stock
  Claude Code, OpenAI Codex, and Fireworks support.
  Triggers: AI usage, subscription usage, omarchy.agents, Antigravity usage, agy usage,
  Claude Code sign-in expired, Antigravity token expired, AI quota panel, bar AI widget.
---

# Omarchy AI Subscription Usage (Improved) Skill

This skill provides complete instructions for autonomous AI coding assistants (Antigravity CLI, Claude Code, Codex, Cursor, etc.) to install, customize, and troubleshoot the enhanced AI Subscription Usage bar plugin on [Omarchy Linux](https://omarchy.org/).

---

## 1. MANDATORY INTERACTIVE DISCOVERY (DO THIS FIRST)

> [!IMPORTANT]
> **NEVER hardcode another user's username, home path, or preferences.**
> Before installing or modifying the plugin on any machine, inspect the current environment (`whoami`, installed AI CLIs) and **ask the user** for their preferences:

1. **Plugin Namespace Prefix**:
   - Omarchy forbids user plugins from using the `omarchy.*` prefix.
   - Default to the target machine's current username (`$(whoami).agents`, e.g., `alice.agents`), or ask if they prefer a custom prefix.
2. **Enabled AI Providers**:
   - Check which CLIs exist on their machine (`agy`, `claude`, `codex`, `firectl`) and ask which tabs they want enabled (`antigravity`, `claude`, `codex`, `fireworks`).
3. **Refresh Interval**:
   - Background refresh interval in seconds (default: `900` seconds / 15 minutes; range `30`–`3600`).
4. **Multi-Device Usage Sync *(Optional)***:
   - Ask whether they want to merge token statistics across multiple machines using a shared folder (Syncthing, Dropbox, rclone cloud drive, etc.). If yes, ask for the sync folder path and optional device name.
5. **Status Bar Placement**:
   - If `omarchy.agents` is already in `~/.config/omarchy/shell.json`, replace it in place. Otherwise, ask which bar section (`left`, `center`, or `right` — default `right`) they want the icon placed in.

---

## 2. CRITICAL TECHNICAL ARCHITECTURE & GOTCHAS

### A. Never Edit `/usr/share/omarchy/`
- `/usr/share/omarchy/` is owned by the system package and overwritten on `omarchy update`.
- Always deploy to `~/.config/omarchy/plugins/<user>.agents/` and reference `<user>.agents` in `~/.config/omarchy/shell.json`.
- In `Main.qml`, resolve `update-usage` dynamically relative to the plugin directory:
  ```qml
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  ```
  Never hardcode `/home/<username>/...` inside QML or scripts.

### B. Why Antigravity CLI (`agy`) Says "Stored Token Is Expired" & How It Is Fixed
- Newer versions of `agy` store and refresh live OAuth credentials in the Freedesktop Secret Service keyring (`secret-tool lookup service gemini username antigravity`), leaving the legacy `~/.gemini/antigravity-cli/antigravity-oauth-token` file stale.
- `collect-antigravity.py` **must** query `secret-tool lookup service gemini username antigravity` first, falling back to `~/.gemini/antigravity-cli/antigravity-oauth-token` only if keyring lookup is unavailable.
- When the token is expired (or if `loadCodeAssist` returns `HTTP 401`), `collect-antigravity.py` runs `agy models` (a read-only command that triggers `agy`'s internal keyring OAuth refresh without starting an LLM turn) and re-reads the refreshed token from the keyring.

### C. Why Claude Code Says "Sign-in Expired" & How It Is Fixed
- Stock `/usr/share/omarchy/bin/omarchy-agent-usage-claude` reads `~/.claude/.credentials.json` and immediately reports `"Sign-in expired"` if `claudeAiOauth.expiresAt` is in the past—even when `claudeAiOauth.refreshToken` is valid.
- `update-usage` checks `~/.claude/.credentials.json` before invoking `omarchy-agent-usage-update`. If `refreshToken` is non-empty and `expiresAt <= now_ms + 60000`, it runs:
  ```bash
  timeout 15 claude auth status >/dev/null 2>&1 || true
  ```
  which causes Claude Code to refresh `.credentials.json` non-interactively using its OAuth refresh token before the stock collector reads it.

### D. In-Panel Refresh & `PanelHero` Scope Rule
- `PanelHero.qml` defines `id: root` internally. Any `Component` assigned to `PanelHero.trailingControl` resolves `root` to `PanelHero`, not the outer `Panel`.
- Expose `readonly property bool refreshing: usage.refreshing` and `function triggerRefresh() { root.refreshNow() }` on the `PanelHero` instance (`id: hero`) so the `PanelActionButton` (`iconText: "󰑐"`) inside `trailingControl` can call `hero.triggerRefresh()`.

---

## 3. INSTALLATION PROCEDURE

### Option A: Automated Script Installation (Recommended)
If this repository is cloned locally, run `install.sh` with the user's chosen flags:
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
*(Or run `./install.sh` interactively in a terminal.)*

### Option B: Direct Agent Setup (Without Repo Clone)
If applying directly onto an Omarchy machine without the repo:
1. Ensure dependencies are installed:
   ```bash
   sudo pacman -S --needed python jq libsecret
   ```
2. Clone the stock plugin using Omarchy's CLI:
   ```bash
   omarchy plugin clone omarchy.agents
   ```
   *(This creates `~/.config/omarchy/plugins/<user>.agents` and updates `~/.config/omarchy/shell.json`.)*
3. Install `collect-antigravity.py` and `update-usage` (with `chmod +x`) into `~/.config/omarchy/plugins/<user>.agents/`.
4. Update `Main.qml` to resolve `root.pluginDir + "/update-usage"` and expose `readonly property bool refreshing: updateProcess.running`.
5. Update `Panel.qml` to:
   - Add the `trailingControl` `PanelActionButton` (`iconText: "󰑐"`) to `PanelHero`.
   - Launch `omarchy-launch-terminal agy` on right-click when `providerId === "antigravity"`.
   - Show all models (`rows`) for `antigravity` instead of slicing to top 4.
6. Run `~/.config/omarchy/plugins/<user>.agents/update-usage --force` and reload plugins:
   ```bash
   omarchy-shell shell rescanPlugins
   ```

---

## 4. VERIFICATION & TROUBLESHOOTING

1. **Verify Collector JSON Output**:
   ```bash
   ~/.config/omarchy/plugins/"$(whoami)".agents/update-usage --force
   jq -c '{id, tierLabel, usageStatusText, limitsCount: (.limits | length)}' \
     ~/.local/state/omarchy/agents/usage/*.json
   ```
   Every active provider should show `"usageStatusText": ""` and non-empty `limitsCount`.
2. **Test Live Shell IPC Refresh**:
   ```bash
   omarchy-shell omarchy.agents refresh
   ```
   Should return `ok`. (Note: do not chain `omarchy-shell shell rescanPlugins && omarchy-shell omarchy.agents refresh` without a brief pause, as `rescanPlugins` reloads the IPC target asynchronously.)
3. **If Antigravity Still Reports Not Logged In**:
   - Check keyring token: `secret-tool lookup service gemini username antigravity | jq '{auth_method, expiry: .token.expiry}'`
   - If empty, have the user run `agy` in a terminal to complete interactive Google OAuth login.
4. **If Claude Code Still Reports Sign-in Expired**:
   - Check `claude auth status`. If the refresh token itself has expired or been revoked, have the user run `claude auth login`.
