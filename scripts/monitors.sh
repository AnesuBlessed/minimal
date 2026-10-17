#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — INTERACTIVE MONITOR & REFRESH-RATE SWITCHER (SUPER + P)
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

CONFIG_PATH="$MINIMAL_ROOT/quickshell/monitors/shell.qml"

if [[ ${1:-} == --fallback ]] || ! command -v quickshell >/dev/null 2>&1; then
    entries="󰍺  Extend Right\n󰍺  Extend Left\n󰍹  Mirror Displays\n󰶐  External Display Only\n󰌢  Laptop Screen Only"
    chosen=$(printf '%b' "$entries" | fuzzel --dmenu --config "$MINIMAL_ROOT/fuzzel/fuzzel.ini" --prompt "󰍹  Monitors: " --lines 5 --width 32 2>/dev/null) || exit 0
    case "${chosen:-}" in
        *"Extend Right"*) exec "$MINIMAL_ROOT/scripts/monitors.py" --preset extend-right ;;
        *"Extend Left"*) exec "$MINIMAL_ROOT/scripts/monitors.py" --preset extend-left ;;
        *"Mirror"*) exec "$MINIMAL_ROOT/scripts/monitors.py" --preset mirror ;;
        *"External"*) exec "$MINIMAL_ROOT/scripts/monitors.py" --preset external-only ;;
        *"Laptop"*) exec "$MINIMAL_ROOT/scripts/monitors.py" --preset internal-only ;;
    esac
    exit 0
fi

mkdir -p -- "$MINIMAL_RUNTIME"
exec 9>"$MINIMAL_RUNTIME/monitors-toggle.lock"
flock -n 9 || exit 0

if [[ ! -r "$MINIMAL_RUNTIME/monitors.pid" ]] && pgrep -u "${UID:-$(id -u)}" -x quickshell >/dev/null 2>&1 && quickshell kill -p "$CONFIG_PATH" >/dev/null 2>&1; then
    exit 0
fi

MINIMAL_MONITORS_JSON=$("$MINIMAL_ROOT/scripts/monitors.py" --state 2>/dev/null || printf '{}')
MINIMAL_POPUP_OUTPUT=$(hyprctl -j monitors 2>/dev/null | jq -r 'first(.[] | select(.focused)).name // empty' || true)
export MINIMAL_MONITORS_JSON MINIMAL_POPUP_OUTPUT
exec "$MINIMAL_ROOT/scripts/popup.sh" monitors quickshell -n -p "$CONFIG_PATH" 9>&-
