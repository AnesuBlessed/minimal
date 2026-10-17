#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — REACTIVE DYNAMIC NOTCH POPUP (MEDIA + WEATHER + RECORDING)
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

CONFIG_PATH="$MINIMAL_ROOT/quickshell/notch/shell.qml"

if [[ ${1:-} == --fallback ]] || ! command -v quickshell >/dev/null 2>&1; then
    entries="󰐎  Play / Pause Media\n󰒭  Next Track\n󰒮  Previous Track\n󰖙  Refresh Weather\n󰑊  Toggle Screen Recording"
    chosen=$(printf '%b' "$entries" | fuzzel --dmenu --config "$MINIMAL_ROOT/fuzzel/fuzzel.ini" --prompt "󰝚  Notch: " --lines 5 --width 34 2>/dev/null) || exit 0
    case "${chosen:-}" in
        *"Play / Pause"*) exec playerctl play-pause ;;
        *"Next Track"*) exec playerctl next ;;
        *"Previous Track"*) exec playerctl previous ;;
        *"Refresh Weather"*) exec "$MINIMAL_ROOT/scripts/notch-status.py" --refresh-weather ;;
        *"Screen Recording"*) exec "$MINIMAL_ROOT/scripts/screenshot.sh" record ;;
    esac
    exit 0
fi

mkdir -p -- "$MINIMAL_RUNTIME"
exec 9>"$MINIMAL_RUNTIME/notch-toggle.lock"
flock -n 9 || exit 0

if [[ ! -r "$MINIMAL_RUNTIME/notch.pid" ]] && pgrep -u "${UID:-$(id -u)}" -x quickshell >/dev/null 2>&1 && quickshell kill -p "$CONFIG_PATH" >/dev/null 2>&1; then
    exit 0
fi

MINIMAL_NOTCH_JSON=$("$MINIMAL_ROOT/scripts/notch-status.py" --popup-json 2>/dev/null || printf '{}')
MINIMAL_POPUP_OUTPUT=$(hyprctl -j monitors 2>/dev/null | jq -r 'first(.[] | select(.focused)).name // empty' || true)
export MINIMAL_NOTCH_JSON MINIMAL_POPUP_OUTPUT
exec "$MINIMAL_ROOT/scripts/popup.sh" notch quickshell -n -p "$CONFIG_PATH" 9>&-
