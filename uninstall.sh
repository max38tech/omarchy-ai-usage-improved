#!/usr/bin/env bash
#
# Omarchy AI Usage Improved — Uninstaller
# Restores stock omarchy.agents in ~/.config/omarchy/shell.json and removes
# the user-owned <user>.agents plugin.
#

set -euo pipefail

DEFAULT_USER="$(whoami)"
PLUGIN_USER=""
NON_INTERACTIVE=false

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --user) PLUGIN_USER="$2"; shift ;;
        --non-interactive) NON_INTERACTIVE=true ;;
        --help|-h)
            echo "Usage: ./uninstall.sh [--user NAME] [--non-interactive]"
            exit 0
            ;;
        *) echo "Unknown parameter: $1" >&2; exit 1 ;;
    esac
    shift
done

if [[ -z "$PLUGIN_USER" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
        PLUGIN_USER="$DEFAULT_USER"
    else
        read -rp "Plugin namespace prefix to uninstall (default: ${DEFAULT_USER} -> ${DEFAULT_USER}.agents): " PLUGIN_USER
        PLUGIN_USER="${PLUGIN_USER:-$DEFAULT_USER}"
    fi
fi

PLUGIN_ID="${PLUGIN_USER}.agents"
TARGET_PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

echo "========================================================"
echo "    Omarchy AI Subscription Usage Uninstaller           "
echo "========================================================"
echo ""

if [[ -f "$SHELL_JSON" ]] && command -v jq >/dev/null 2>&1; then
    echo "[-] Restoring stock 'omarchy.agents' in $SHELL_JSON..."
    jq --arg pid "$PLUGIN_ID" '
        def restore_agents:
            map(if type == "object" and .id == $pid then .id = "omarchy.agents"
                elif type == "string" and . == $pid then "omarchy.agents"
                else . end);
        if .bar?.layout then
            .bar.layout.left = ((.bar.layout.left // []) | restore_agents) |
            .bar.layout.center = ((.bar.layout.center // []) | restore_agents) |
            .bar.layout.right = ((.bar.layout.right // []) | restore_agents)
        else
            .
        end
    ' "$SHELL_JSON" > "${SHELL_JSON}.tmp" && mv "${SHELL_JSON}.tmp" "$SHELL_JSON"
fi

if [[ -d "$TARGET_PLUGIN_DIR" ]]; then
    echo "[-] Removing plugin directory $TARGET_PLUGIN_DIR..."
    rm -rf "$TARGET_PLUGIN_DIR"
fi

REMOVE_CACHE="false"
if [[ "$NON_INTERACTIVE" == false ]]; then
    read -rp "Remove cached Antigravity usage state (~/.local/state/omarchy/agents/usage/antigravity.json) and skill? [y/N]: " REPLY_CACHE
    [[ "$REPLY_CACHE" =~ ^[Yy]$ ]] && REMOVE_CACHE="true"
fi

if [[ "$REMOVE_CACHE" == "true" ]]; then
    STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents"
    rm -f "$STATE_DIR/usage/antigravity.json" "$STATE_DIR/antigravity-stats.json" "$STATE_DIR/antigravity.lock"
    rm -rf "$HOME/.agents/skills/omarchy-ai-usage"
    echo "[+] Cached Antigravity usage state and skill removed."
fi

if command -v omarchy-shell >/dev/null 2>&1; then
    echo "[-] Reloading Omarchy shell plugins..."
    omarchy-shell -q shell rescanPlugins || true
fi

echo ""
echo "[+] Uninstalled $PLUGIN_ID and restored stock omarchy.agents."
