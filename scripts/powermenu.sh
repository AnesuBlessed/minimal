#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — POWER MENU (STANDALONE WLOGOUT LAUNCHER)
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"


if command -v wlogout >/dev/null 2>&1; then
    confDir="$MINIMAL_CONFIG/wlogout"
    layout="$confDir/layout"
    [[ -f $layout ]] || layout="$MINIMAL_ROOT/wlogout/layout"

    # Use logical dimensions and stable cards; hovering never moves a target.
    read -r width height < <(hyprctl -j monitors 2>/dev/null | jq -r '
        (first(.[] | select(.focused)) // .[0]) |
        [((if (.transform % 2) == 1 then .height else .width end) / .scale | floor),
         ((if (.transform % 2) == 1 then .width else .height end) / .scale | floor)] | @tsv') || true
    [[ ${width:-} =~ ^[0-9]+$ ]] || width=1366
    [[ ${height:-} =~ ^[0-9]+$ ]] || height=768
    columns=6; panel_width=816; panel_height=144
    if ((width < 900)); then columns=3; panel_width=432; panel_height=296; fi
    ((panel_width <= width - 24)) || panel_width=$((width - 24))
    side=$(((width - panel_width) / 2))
    vertical=$(((height - panel_height) / 2))
    ((vertical >= 12)) || vertical=12
    exec "$MINIMAL_ROOT/scripts/popup.sh" power wlogout -b "$columns" -c 8 -r 8 \
        -L "$side" -R "$side" -T "$vertical" -B "$vertical" \
        --layout "$layout" --css "$MINIMAL_ROOT/wlogout/style.css" --protocol layer-shell

else
    # Fuzzel dmenu fallback if wlogout is unavailable
    entries="󰌾  Lock\n󰤄  Suspend\n󰒲  Hibernate\n󰍃  Logout\n󰜉  Reboot\n󰐥  Shutdown"
    chosen=$(printf '%b' "$entries" | fuzzel --dmenu --config "$MINIMAL_ROOT/fuzzel/fuzzel.ini" --prompt "󰐥  Power: " --lines 6 --width 20 2>/dev/null) || exit 0
    case "${chosen:-}" in
        *"Lock"*) exec "$MINIMAL_ROOT/scripts/lock.sh" ;;
        *"Suspend"*) exec "$MINIMAL_ROOT/scripts/power-action.sh" suspend ;;
        *"Hibernate"*) exec "$MINIMAL_ROOT/scripts/power-action.sh" hibernate ;;
        *"Logout"*) exec "$MINIMAL_ROOT/scripts/power-action.sh" logout ;;
        *"Reboot"*) exec "$MINIMAL_ROOT/scripts/power-action.sh" reboot ;;
        *"Shutdown"*) exec "$MINIMAL_ROOT/scripts/power-action.sh" poweroff ;;
    esac
fi
