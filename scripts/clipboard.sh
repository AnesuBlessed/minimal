#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — CLIPBOARD MANAGER LAUNCHER & TOGGLE
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

CONFIG_PATH="$MINIMAL_ROOT/quickshell/clipboard/shell.qml"

# Fallback immediately to fuzzel dmenu if quickshell is not available
if [[ ${1:-} == --fallback ]] || ! command -v quickshell >/dev/null 2>&1; then
    selected=$(cliphist list | fuzzel --dmenu --config "$MINIMAL_ROOT/fuzzel/fuzzel.ini") || exit 0
    [[ -n $selected ]] || exit 0
    "$MINIMAL_ROOT/scripts/clipboard-action.sh" copy "${selected%%$'\t'*}"
    exit 0
fi

mkdir -p -- "$MINIMAL_RUNTIME"
exec 9>"$MINIMAL_RUNTIME/clipboard-toggle.lock"
flock -n 9 || exit 0

# Fast PID-tracked toggle if managed by popup.sh; fallback to quickshell kill -p if started directly.
if [[ ! -r "$MINIMAL_RUNTIME/clipboard.pid" ]] && pgrep -u "${UID:-$(id -u)}" -x quickshell >/dev/null 2>&1 && quickshell kill -p "$CONFIG_PATH" >/dev/null 2>&1; then
    exit 0
fi

export QS_CACHE_CLIPBOARD="$MINIMAL_CACHE/clipboard"
export QS_RUN_CLIPBOARD="$MINIMAL_RUNTIME/clipboard"

MINIMAL_POPUP_OUTPUT=$(hyprctl -j monitors 2>/dev/null | jq -r 'first(.[] | select(.focused)).name // empty' || true)
export MINIMAL_POPUP_OUTPUT
exec "$MINIMAL_ROOT/scripts/popup.sh" clipboard quickshell -n -p "$CONFIG_PATH" 9>&-
