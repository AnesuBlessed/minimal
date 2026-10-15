#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — POWER MENU (STANDALONE WLOGOUT LAUNCHER)
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

if pkill -x wlogout; then
    exit 0
fi

if command -v wlogout >/dev/null 2>&1; then
    confDir="${XDG_CONFIG_HOME:-$HOME/.config}/wlogout"
    layout="$confDir/layout"
    style="$confDir/style.css"
    [[ -f $layout ]] || layout="$MINIMAL_ROOT/wlogout/layout"
    [[ -f $style ]] || style="$MINIMAL_ROOT/wlogout/style.css"

    exec wlogout -b 6 -c 0 -r 0 -m 0 --layout "$layout" --css "$style" --protocol layer-shell
else
    # Fuzzel dmenu fallback if wlogout is unavailable
    entries="󰌾  Lock\n󰤄  Suspend\n󰍃  Logout\n󰜉  Reboot\n󰐥  Shutdown"
    chosen=$(printf '%b' "$entries" | fuzzel --dmenu --config "$MINIMAL_ROOT/fuzzel/fuzzel.ini" --prompt "󰐥  Power: " --lines 5 --width 20 2>/dev/null) || exit 0
    case "${chosen:-}" in
        *"Lock"*) exec "$MINIMAL_ROOT/scripts/lock.sh" ;;
        *"Suspend"*) exec systemctl suspend ;;
        *"Logout"*) exec hyprctl dispatch exit ;;
        *"Reboot"*) exec systemctl reboot ;;
        *"Shutdown"*) exec systemctl poweroff ;;
    esac
fi
