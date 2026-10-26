#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — POWER MENU (WLOGOUT + ROFI FALLBACK)
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

# Toggle: close if already open
if pgrep -x "wlogout" >/dev/null 2>&1; then
    pkill -x "wlogout"
    exit 0
fi

if command -v wlogout >/dev/null 2>&1; then
    wLayout="$MINIMAL_ROOT/wlogout/layout"
    wStyle="$MINIMAL_ROOT/wlogout/style.css"
    
    # Process layout and CSS with MINIMAL_ROOT path expansion
    tmpLayout=$(mktemp --suffix=.json)
    tmpStyle=$(mktemp --suffix=.css)
    trap 'rm -f -- "$tmpLayout" "$tmpStyle"' EXIT
    sed "s|\$MINIMAL_ROOT|$MINIMAL_ROOT|g" "$wLayout" > "$tmpLayout"
    sed "s|url(\"icons/|url(\"$MINIMAL_ROOT/wlogout/icons/|g" "$wStyle" > "$tmpStyle"
    
    exec wlogout -b 6 -c 0 -r 0 -m 0 --layout "$tmpLayout" --css "$tmpStyle" --protocol layer-shell
fi

# Fallback: Clean Rofi menu
entries="󰌾  Lock\n󰤄  Suspend\n󰍃  Logout\n󰜉  Reboot\n󰐥  Shutdown"
chosen=$(printf '%b' "$entries" | rofi -dmenu -theme "$MINIMAL_ROOT/rofi/selector.rasi" -p "󰐥 Power: " 2>/dev/null) || exit 0

case "${chosen:-}" in
    *"Lock"*)
        "$MINIMAL_ROOT/scripts/lock.sh"
        ;;
    *"Suspend"*)
        systemctl suspend
        ;;
    *"Logout"*)
        hyprctl dispatch exit
        ;;
    *"Reboot"*)
        systemctl reboot
        ;;
    *"Shutdown"*)
        systemctl poweroff
        ;;
esac
