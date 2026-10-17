#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — INTERACTIVE KEYBIND CHEAT-SHEET POPUP & FALLBACK
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

CONFIG_PATH="$MINIMAL_ROOT/quickshell/keybinds/shell.qml"

if [[ ${1:-} == --fallback ]] || ! command -v quickshell >/dev/null 2>&1; then
    "$MINIMAL_ROOT/scripts/parse-keybinds.py" --dmenu \
        | fuzzel --dmenu --config "$MINIMAL_ROOT/fuzzel/fuzzel.ini" --prompt "󰌌  Keybinds: " --lines 10 --width 52 || true
    exit 0
fi

mkdir -p -- "$MINIMAL_RUNTIME"
exec 9>"$MINIMAL_RUNTIME/keybinds-toggle.lock"
flock -n 9 || exit 0

if [[ ! -r "$MINIMAL_RUNTIME/keybinds.pid" ]] && pgrep -u "${UID:-$(id -u)}" -x quickshell >/dev/null 2>&1 && quickshell kill -p "$CONFIG_PATH" >/dev/null 2>&1; then
    exit 0
fi

MINIMAL_KEYBINDS_JSON=$("$MINIMAL_ROOT/scripts/parse-keybinds.py" --json)
MINIMAL_POPUP_OUTPUT=$(hyprctl -j monitors 2>/dev/null | jq -r 'first(.[] | select(.focused)).name // empty' || true)
export MINIMAL_KEYBINDS_JSON MINIMAL_POPUP_OUTPUT
exec "$MINIMAL_ROOT/scripts/popup.sh" keybinds quickshell -n -p "$CONFIG_PATH" 9>&-
