#!/usr/bin/env bash
#
# Omarchy AI Usage Improved — Interactive & Scriptable Installer
# Adds Antigravity CLI (agy) usage & quota tracking, automatic OAuth token
# renewal for Antigravity (keyring) and Claude Code, and an in-panel refresh
# button to the Omarchy AI Subscription Usage bar widget.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_USER="$(whoami)"

PLUGIN_USER=""
REFRESH_INTERVAL=""
ENABLE_ANTIGRAVITY=""
ENABLE_CLAUDE=""
ENABLE_CODEX=""
ENABLE_FIREWORKS=""
SYNC_MODE=""
SYNC_DIR=""
SYNC_FILE_NAME=""
SYNC_DEVICE_ID=""
BAR_SECTION=""
INSTALL_SKILL=""
NON_INTERACTIVE=false

usage() {
    cat <<EOF
Usage: ./install.sh [OPTIONS]

Options:
  --user NAME                 Plugin namespace prefix (default: current user '$DEFAULT_USER' -> <user>.agents)
  --refresh-interval SEC      Background refresh interval in seconds (30-3600, default: 900)
  --enable-antigravity BOOL   Enable Antigravity CLI provider (true|false)
  --enable-claude BOOL        Enable Claude Code provider (true|false)
  --enable-codex BOOL         Enable OpenAI Codex provider (true|false)
  --enable-fireworks BOOL     Enable Fireworks AI provider (true|false)
  --sync-mode MODE            Multi-device usage sync ('Off' or 'On', default: Off)
  --sync-dir PATH             Folder path for multi-device sync when sync-mode is On
  --sync-file NAME            Optional snapshot filename (default: <hostname>.json)
  --sync-device-id ID         Optional device ID for multi-device sync
  --bar-section SECTION       Bar section if not already on bar (left|center|right, default: right)
  --install-skill BOOL        Install SKILL.md to ~/.agents/skills/omarchy-ai-usage/ (true|false)
  --non-interactive           Use defaults/flags without interactive prompts
  --help, -h                  Show this help message
EOF
}

normalize_bool() {
    local val="${1:-}"
    case "${val,,}" in
        true|yes|y|1|on) echo "true" ;;
        false|no|n|0|off) echo "false" ;;
        *) echo "$2" ;;
    esac
}

prompt_yes_no() {
    local prompt_text="$1"
    local default_val="$2"
    local hint="[Y/n]"
    [[ "$default_val" == "false" ]] && hint="[y/N]"
    local reply=""
    read -rp "$prompt_text $hint: " reply
    if [[ -z "$reply" ]]; then
        echo "$default_val"
    else
        normalize_bool "$reply" "$default_val"
    fi
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --user) PLUGIN_USER="$2"; shift ;;
        --refresh-interval) REFRESH_INTERVAL="$2"; shift ;;
        --enable-antigravity) ENABLE_ANTIGRAVITY="$(normalize_bool "$2" "true")"; shift ;;
        --enable-claude) ENABLE_CLAUDE="$(normalize_bool "$2" "true")"; shift ;;
        --enable-codex) ENABLE_CODEX="$(normalize_bool "$2" "true")"; shift ;;
        --enable-fireworks) ENABLE_FIREWORKS="$(normalize_bool "$2" "true")"; shift ;;
        --sync-mode) SYNC_MODE="$2"; shift ;;
        --sync-dir) SYNC_DIR="$2"; shift ;;
        --sync-file) SYNC_FILE_NAME="$2"; shift ;;
        --sync-device-id) SYNC_DEVICE_ID="$2"; shift ;;
        --bar-section) BAR_SECTION="$2"; shift ;;
        --install-skill) INSTALL_SKILL="$(normalize_bool "$2" "true")"; shift ;;
        --non-interactive) NON_INTERACTIVE=true ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown parameter: $1" >&2; usage; exit 1 ;;
    esac
    shift
done

echo "========================================================"
echo "    Omarchy AI Subscription Usage (Improved) Installer  "
echo "========================================================"
echo ""

# Auto-detect installed AI CLIs/configs to offer smart defaults
HAS_AGY="false"
if command -v agy >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/agy" ]] || [[ -d "$HOME/.gemini/antigravity-cli" ]]; then
    HAS_AGY="true"
fi
HAS_CLAUDE="false"
if command -v claude >/dev/null 2>&1 || [[ -d "$HOME/.claude" ]]; then
    HAS_CLAUDE="true"
fi
HAS_CODEX="false"
if command -v codex >/dev/null 2>&1 || [[ -d "$HOME/.codex" ]]; then
    HAS_CODEX="true"
fi
HAS_FIREWORKS="false"
if command -v firectl >/dev/null 2>&1 || [[ -n "${FIREWORKS_API_KEY:-}" ]]; then
    HAS_FIREWORKS="true"
fi

# 1. Plugin namespace
if [[ -z "$PLUGIN_USER" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
        PLUGIN_USER="$DEFAULT_USER"
    else
        read -rp "1. Plugin namespace prefix (default: ${DEFAULT_USER} -> ${DEFAULT_USER}.agents): " PLUGIN_USER
        PLUGIN_USER="${PLUGIN_USER:-$DEFAULT_USER}"
    fi
fi
# Sanitize namespace (Omarchy forbids 'omarchy.*' for user plugins)
PLUGIN_USER="$(echo "$PLUGIN_USER" | tr -cd 'a-zA-Z0-9_-')"
if [[ -z "$PLUGIN_USER" || "${PLUGIN_USER,,}" == "omarchy" ]]; then
    echo "[!] Note: Omarchy reserves 'omarchy.*' for stock plugins. Using '${DEFAULT_USER}' instead."
    PLUGIN_USER="$DEFAULT_USER"
fi
PLUGIN_ID="${PLUGIN_USER}.agents"

# 2. Providers to enable
if [[ "$NON_INTERACTIVE" == false ]]; then
    echo ""
    echo "2. Select which AI subscription providers to enable in the panel"
    echo "   (Detected on this machine: agy=${HAS_AGY}, claude=${HAS_CLAUDE}, codex=${HAS_CODEX}, fireworks=${HAS_FIREWORKS}):"
fi

if [[ -z "$ENABLE_ANTIGRAVITY" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
        ENABLE_ANTIGRAVITY="true"
    else
        ENABLE_ANTIGRAVITY="$(prompt_yes_no "   - Enable Antigravity CLI (agy)?" "true")"
    fi
fi

if [[ -z "$ENABLE_CLAUDE" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
        ENABLE_CLAUDE="true"
    else
        ENABLE_CLAUDE="$(prompt_yes_no "   - Enable Claude Code?" "true")"
    fi
fi

if [[ -z "$ENABLE_CODEX" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
        ENABLE_CODEX="true"
    else
        ENABLE_CODEX="$(prompt_yes_no "   - Enable OpenAI Codex?" "true")"
    fi
fi

if [[ -z "$ENABLE_FIREWORKS" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
        ENABLE_FIREWORKS="true"
    else
        ENABLE_FIREWORKS="$(prompt_yes_no "   - Enable Fireworks AI?" "$HAS_FIREWORKS")"
    fi
fi

# 3. Refresh interval
if [[ -z "$REFRESH_INTERVAL" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
        REFRESH_INTERVAL="900"
    else
        echo ""
        read -rp "3. Background refresh interval in seconds (30-3600, default: 900): " REFRESH_INTERVAL
        REFRESH_INTERVAL="${REFRESH_INTERVAL:-900}"
    fi
fi
if ! [[ "$REFRESH_INTERVAL" =~ ^[0-9]+$ ]] || (( REFRESH_INTERVAL < 30 )) || (( REFRESH_INTERVAL > 3600 )); then
    REFRESH_INTERVAL="900"
fi

# 4. Multi-device sync
if [[ -z "$SYNC_MODE" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
        SYNC_MODE="Off"
    else
        echo ""
        USE_SYNC="$(prompt_yes_no "4. Enable multi-device usage sync (via Syncthing, Dropbox, Cloud Drive, etc.)?" "false")"
        if [[ "$USE_SYNC" == "true" ]]; then
            SYNC_MODE="On"
        else
            SYNC_MODE="Off"
        fi
    fi
fi

if [[ "${SYNC_MODE,,}" == "on" || "${SYNC_MODE,,}" == "true" ]]; then
    SYNC_MODE="On"
    if [[ -z "$SYNC_DIR" && "$NON_INTERACTIVE" == false ]]; then
        read -rp "   - Sync folder path (e.g. ~/Dropbox/omarchy-agents or ~/Sync/omarchy-agents): " SYNC_DIR
    fi
    if [[ -z "$SYNC_DEVICE_ID" && "$NON_INTERACTIVE" == false ]]; then
        DEFAULT_HOST="$(cat /etc/hostname 2>/dev/null || hostname || echo "device")"
        read -rp "   - Device ID for this machine (default: ${DEFAULT_HOST}): " SYNC_DEVICE_ID
        SYNC_DEVICE_ID="${SYNC_DEVICE_ID:-$DEFAULT_HOST}"
    fi
    if [[ -z "$SYNC_FILE_NAME" && "$NON_INTERACTIVE" == false ]]; then
        read -rp "   - Snapshot filename (optional, default: ${SYNC_DEVICE_ID:-$(hostname)}.json): " SYNC_FILE_NAME
    fi
else
    SYNC_MODE="Off"
fi

# 5. Bar placement
SHELL_JSON="$HOME/.config/omarchy/shell.json"
if [[ -z "$BAR_SECTION" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
        BAR_SECTION="right"
    elif [[ -f "$SHELL_JSON" ]] && ! grep -qE '"(omarchy|'"$PLUGIN_USER"'\.)agents"' "$SHELL_JSON"; then
        echo ""
        read -rp "5. Bar section for the widget (left|center|right, default: right): " BAR_SECTION
        BAR_SECTION="${BAR_SECTION:-right}"
    else
        BAR_SECTION="right"
    fi
fi
case "${BAR_SECTION,,}" in
    left|center|right) BAR_SECTION="${BAR_SECTION,,}" ;;
    *) BAR_SECTION="right" ;;
esac

# 6. Agent skill installation
if [[ -z "$INSTALL_SKILL" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
        INSTALL_SKILL="true"
    else
        echo ""
        INSTALL_SKILL="$(prompt_yes_no "5. Install AI Agent Skill (SKILL.md) to ~/.agents/skills/omarchy-ai-usage/?" "true")"
    fi
fi

echo ""
echo "[-] Verifying system prerequisites..."
MISSING_PKGS=()
command -v python3 >/dev/null 2>&1 || MISSING_PKGS+=("python")
command -v jq >/dev/null 2>&1 || MISSING_PKGS+=("jq")
command -v secret-tool >/dev/null 2>&1 || MISSING_PKGS+=("libsecret")

if (( ${#MISSING_PKGS[@]} > 0 )); then
    echo "[!] Missing packages: ${MISSING_PKGS[*]}"
    if command -v pacman >/dev/null 2>&1; then
        echo "[*] Installing missing dependencies via pacman..."
        sudo pacman -S --needed --noconfirm "${MISSING_PKGS[@]}"
    else
        echo "Please install ${MISSING_PKGS[*]} using your system package manager." >&2
        exit 1
    fi
fi
echo "[+] Dependencies verified."

# Install Quickshell plugin
TARGET_PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
echo "[-] Installing Quickshell plugin to $TARGET_PLUGIN_DIR..."
mkdir -p "$TARGET_PLUGIN_DIR/assets"

cp "$SCRIPT_DIR/plugin/Agent.qml" "$TARGET_PLUGIN_DIR/"
cp "$SCRIPT_DIR/plugin/Main.qml" "$TARGET_PLUGIN_DIR/"
cp "$SCRIPT_DIR/plugin/Panel.qml" "$TARGET_PLUGIN_DIR/"
cp "$SCRIPT_DIR/plugin/ANTIGRAVITY.md" "$TARGET_PLUGIN_DIR/"
cp "$SCRIPT_DIR/plugin/update-usage" "$TARGET_PLUGIN_DIR/"
cp "$SCRIPT_DIR/plugin/collect-antigravity.py" "$TARGET_PLUGIN_DIR/"
cp "$SCRIPT_DIR/plugin/assets/"* "$TARGET_PLUGIN_DIR/assets/"
chmod +x "$TARGET_PLUGIN_DIR/update-usage" "$TARGET_PLUGIN_DIR/collect-antigravity.py"

sed \
    -e "s|{{USER_PLUGIN_ID}}|$PLUGIN_ID|g" \
    -e "s|{{USER_NAME}}|$PLUGIN_USER|g" \
    -e "s|{{ENABLE_ANTIGRAVITY}}|$ENABLE_ANTIGRAVITY|g" \
    -e "s|{{ENABLE_CLAUDE}}|$ENABLE_CLAUDE|g" \
    -e "s|{{ENABLE_CODEX}}|$ENABLE_CODEX|g" \
    -e "s|{{ENABLE_FIREWORKS}}|$ENABLE_FIREWORKS|g" \
    -e "s|{{REFRESH_INTERVAL}}|$REFRESH_INTERVAL|g" \
    -e "s|{{SYNC_MODE}}|$SYNC_MODE|g" \
    -e "s|{{SYNC_DIR}}|$SYNC_DIR|g" \
    -e "s|{{SYNC_FILE_NAME}}|$SYNC_FILE_NAME|g" \
    -e "s|{{SYNC_DEVICE_ID}}|$SYNC_DEVICE_ID|g" \
    "$SCRIPT_DIR/plugin/manifest.json.template" > "$TARGET_PLUGIN_DIR/manifest.json"

# Update ~/.config/omarchy/shell.json
if [[ ! -f "$SHELL_JSON" ]] && [[ -f "/usr/share/omarchy/config/omarchy/shell.json" ]]; then
    mkdir -p "$(dirname "$SHELL_JSON")"
    cp "/usr/share/omarchy/config/omarchy/shell.json" "$SHELL_JSON"
fi

if [[ -f "$SHELL_JSON" ]]; then
    BACKUP_PATH="${SHELL_JSON}.bak.$(date +%s)"
    cp "$SHELL_JSON" "$BACKUP_PATH"
    echo "[-] Backed up shell.json to $BACKUP_PATH"
    echo "[-] Registering $PLUGIN_ID in $SHELL_JSON..."
    jq --arg pid "$PLUGIN_ID" --arg sec "$BAR_SECTION" '
        def replace_agents:
            map(if type == "object" and (.id == "omarchy.agents" or (.id | tostring | endswith(".agents"))) then .id = $pid
                elif type == "string" and (. == "omarchy.agents" or endswith(".agents")) then $pid
                else . end);
        if .bar?.layout then
            .bar.layout.left = ((.bar.layout.left // []) | replace_agents) |
            .bar.layout.center = ((.bar.layout.center // []) | replace_agents) |
            .bar.layout.right = ((.bar.layout.right // []) | replace_agents) |
            if ([.bar.layout.left[], .bar.layout.center[], .bar.layout.right[]] | any((type == "object" and .id == $pid) or . == $pid)) then
                .
            else
                .bar.layout[$sec] = ([{ "id": $pid }] + (.bar.layout[$sec] // []))
            end
        else
            .
        end
    ' "$SHELL_JSON" > "${SHELL_JSON}.tmp" && mv "${SHELL_JSON}.tmp" "$SHELL_JSON"
fi

# Install AI Agent Skill if requested
if [[ "$INSTALL_SKILL" == "true" ]]; then
    SKILL_DIR="$HOME/.agents/skills/omarchy-ai-usage"
    echo "[-] Installing AI Agent Skill to $SKILL_DIR/SKILL.md..."
    mkdir -p "$SKILL_DIR"
    cp "$SCRIPT_DIR/SKILL.md" "$SKILL_DIR/SKILL.md"
fi

# Run initial usage collection and reload Omarchy shell
echo "[-] Running initial usage & quota collection..."
"$TARGET_PLUGIN_DIR/update-usage" --force || true

if command -v omarchy-shell >/dev/null 2>&1; then
    echo "[-] Reloading Omarchy shell plugins..."
    omarchy-shell -q shell rescanPlugins || true
fi

echo ""
echo "========================================================"
echo "    Installation Complete!                              "
echo "========================================================"
echo ""
echo "Installed plugin : $PLUGIN_ID ($TARGET_PLUGIN_DIR)"
echo "Controls         :"
echo "  - Left-click bar icon (󱚣)  : Open AI Subscription Usage panel"
echo "  - Click 󰑐 in panel header  : Force refresh all usage & OAuth limits"
echo "  - Press R / Enter in panel : Force refresh all usage & OAuth limits"
echo "  - Right-click bar icon     : Launch agy (when Antigravity tab is active) or agent picker"
echo "  - CLI refresh              : omarchy-shell omarchy.agents refresh"
echo ""
