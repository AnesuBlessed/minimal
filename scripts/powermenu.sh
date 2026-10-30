#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — POWER MENU (WLOGOUT + ROFI FALLBACK)
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

# Toggle: close if already open
if pgrep -u "$(id -u)" -x "wlogout" >/dev/null 2>&1; then
    pkill -u "$(id -u)" -x "wlogout"
    exit 0
fi

if command -v wlogout >/dev/null 2>&1; then
    wLayout="$MINIMAL_ROOT/wlogout/layout"
    wStyle="$MINIMAL_ROOT/wlogout/style.css"
    [[ ! -f "$MINIMAL_STATE/theme/wlogout.css" ]] || wStyle="$MINIMAL_STATE/theme/wlogout.css"
    
    # JSON-encode the resolved action and CSS path; checkout paths may contain spaces.
    tmpLayout=$(mktemp --suffix=.json)
    tmpStyle=$(mktemp --suffix=.css)
    trap 'rm -f -- "$tmpLayout" "$tmpStyle"' EXIT
    "$MINIMAL_ROOT/scripts/native.sh" power-files "$wLayout" "$wStyle" "$tmpLayout" "$tmpStyle"
    # Centered floating horizontal dock with identical square buttons (116x116px)
    mon_w=1366
    mon_h=768
    if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        active_mon=$(hyprctl monitors -j 2>/dev/null | jq -r '(.[] | select(.focused == true) // .[0]) | "\(.width) \(.height)"' 2>/dev/null || true)
        if [[ -n "$active_mon" ]]; then
            read -r mon_w mon_h <<< "$active_mon"
        fi
    fi

    btn_size=116
    gap=16
    total_w=$(( 6 * btn_size + 5 * gap ))
    margin_v=$(( (mon_h - btn_size) / 2 ))
    margin_h=$(( (mon_w - total_w) / 2 ))
    if (( margin_v < 0 )); then margin_v=0; fi
    if (( margin_h < 0 )); then margin_h=0; fi

    wlogout -b 6 -c "$gap" -r 0 -T "$margin_v" -B "$margin_v" -L "$margin_h" -R "$margin_h" \
        --layout "$tmpLayout" --css "$tmpStyle" -p xdg
    exit $?

fi

# Fallback: Clean Rofi menu (toggles closed if already open; switches if another rofi is open)
uid="${UID:-$(id -u)}"
if pgrep -u "$uid" -f "rofi.*selector\.rasi" >/dev/null 2>&1; then
    pkill -u "$uid" -f "rofi.*selector\.rasi"
    exit 0
fi
pkill -u "$uid" -x rofi 2>/dev/null || true
entries="󰌾  Lock\n󰤄  Suspend\n󰋊  Hibernate\n󰍃  Logout\n󰜉  Reboot\n󰐥  Shutdown"
chosen=$(printf '%b' "$entries" | rofi -dmenu -theme "$MINIMAL_ROOT/rofi/selector.rasi" -theme-str "$("$MINIMAL_ROOT/scripts/rofi-images.sh" selector 2>/dev/null || "$MINIMAL_ROOT/scripts/theme.sh" --rofi)" -p "󰐥 Power: " 2>/dev/null) || exit 0

case "${chosen:-}" in
    *"Lock"*)
        "$MINIMAL_ROOT/scripts/lock.sh"
        ;;
    *"Suspend"*)
        "$MINIMAL_ROOT/scripts/lock.sh" & sleep 1
        systemctl suspend
        ;;
    *"Hibernate"*)
        "$MINIMAL_ROOT/scripts/lock.sh" & sleep 1
        systemctl hibernate
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
