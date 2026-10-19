#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — UNIFIED QUICKSHELL CONTROL CENTER (WI-FI, BLUETOOTH, AUDIO, DISPLAY)
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

CONFIG_PATH="$MINIMAL_ROOT/quickshell/control-center/shell.qml"
TAB="${1:-quick}"
case "$TAB" in
    quick|wifi|bluetooth|audio) ;;
    --fallback) TAB="quick" ;;
    *) TAB="quick" ;;
esac

mkdir -p -- "$MINIMAL_RUNTIME" "$MINIMAL_CACHE"
exec 9>"$MINIMAL_RUNTIME/control-center-toggle.lock"
flock -n 9 || exit 0

if [[ ! -r "$MINIMAL_RUNTIME/control-center.pid" ]] && pgrep -u "${UID:-$(id -u)}" -x quickshell >/dev/null 2>&1 && quickshell kill -p "$CONFIG_PATH" >/dev/null 2>&1; then
    exit 0
fi

MINIMAL_CC_TAB="$TAB"
MINIMAL_CC_JSON=$(cat "$MINIMAL_CACHE/cc-state.json" 2>/dev/null || printf '{}')
MINIMAL_POPUP_OUTPUT=$(hyprctl -j monitors 2>/dev/null | jq -r 'first(.[] | select(.focused)).name // empty' || true)
export MINIMAL_CC_TAB MINIMAL_CC_JSON MINIMAL_POPUP_OUTPUT
exec "$MINIMAL_ROOT/scripts/popup.sh" control-center quickshell -n -p "$CONFIG_PATH" 9>&-
