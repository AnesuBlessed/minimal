#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — CLIPBOARD MANAGER LAUNCHER & TOGGLE
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

CONFIG_PATH="$MINIMAL_ROOT/quickshell/clipboard/shell.qml"
CONFIG_DIR="$MINIMAL_ROOT/quickshell/clipboard"

# Fallback immediately to fuzzel dmenu if quickshell is not available
if ! command -v quickshell >/dev/null 2>&1; then
    cliphist list | fuzzel --dmenu | cliphist decode | wl-copy
    exit 0
fi

# Quickshell toggle: if already running the clipboard manager, close it.
if pgrep -f "quickshell.*clipboard" >/dev/null 2>&1; then
    quickshell kill -p "$CONFIG_PATH" >/dev/null 2>&1 || pkill -f "quickshell.*clipboard" || true
    exit 0
fi

export QS_CACHE_CLIPBOARD="$MINIMAL_CACHE/clipboard"
export QS_RUN_CLIPBOARD="$MINIMAL_RUNTIME/clipboard"

exec quickshell -n -p "$CONFIG_PATH"
