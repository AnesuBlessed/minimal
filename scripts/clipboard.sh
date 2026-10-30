#!/usr/bin/env bash
# Compact clipboard: click a clip to copy, its × to delete, or the broom to clear.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

ROFI_THEME="$MINIMAL_ROOT/rofi/clipboard.rasi"
placement="$("$MINIMAL_ROOT/scripts/clipboard-placement.sh") $("$MINIMAL_ROOT/scripts/rofi-images.sh" clipboard)"

# Both the keybind and bar open (or close) this same compact view.
uid="${UID:-$(id -u)}"
if pgrep -u "$uid" -f "rofi.*clipboard\\.rasi" >/dev/null 2>&1; then
    pkill -u "$uid" -f "rofi.*clipboard\\.rasi" || true
    exit 0
fi
pkill -u "$uid" -x rofi 2>/dev/null || true
if [[ ! -f "$MINIMAL_CACHE/wall.quad" ]]; then
    "$MINIMAL_ROOT/scripts/rofi-banner.sh" >/dev/null 2>&1 || true
fi

# Script mode refreshes entries inside one Rofi window instead of restarting dmenu.
export MINIMAL_CLIPBOARD_START="${1:-}"
exec rofi -no-config -show clipboard \
    -modes "clipboard:$MINIMAL_ROOT/scripts/clipboard-mode.sh" \
    -hover-select -theme "$ROFI_THEME" -theme-str "$placement" \
    -kb-delete-entry '' -kb-custom-1 'Shift+Delete' -kb-custom-2 'Control+Shift+Delete'
