#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — NOTIFICATION CONTROLS (DISMISS, RECALL, DO NOT DISTURB)
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

action=${1:-dismiss}

case "$action" in
    dismiss)
        if command -v makoctl >/dev/null 2>&1 && makoctl dismiss 2>/dev/null; then
            exit 0
        elif command -v dunstctl >/dev/null 2>&1; then
            dunstctl close 2>/dev/null || true
        fi
        ;;
    dismiss-all)
        if command -v makoctl >/dev/null 2>&1 && makoctl dismiss -a 2>/dev/null; then
            exit 0
        elif command -v dunstctl >/dev/null 2>&1; then
            dunstctl close-all 2>/dev/null || true
        fi
        ;;
    restore)
        if command -v makoctl >/dev/null 2>&1 && makoctl restore 2>/dev/null; then
            exit 0
        elif command -v dunstctl >/dev/null 2>&1; then
            dunstctl history-pop 2>/dev/null || true
        fi
        ;;
    dnd)
        if command -v makoctl >/dev/null 2>&1 && makoctl mode >/dev/null 2>&1; then
            current_modes=$(makoctl mode 2>/dev/null || echo "")
            if [[ $current_modes == *"dnd"* ]]; then
                makoctl mode -r dnd 2>/dev/null || true
                notify-send -a minimal-notif -t 2500 \
                    -h string:x-canonical-private-synchronous:dnd \
                    "󰂚  Notifications Active" "Do Not Disturb has been disabled."
            else
                notify-send -a minimal-notif -t 2500 \
                    -h string:x-canonical-private-synchronous:dnd \
                    "󰂛  Do Not Disturb" "Notifications are now silenced."
                sleep 0.5
                makoctl mode -a dnd 2>/dev/null || true
            fi
        elif command -v dunstctl >/dev/null 2>&1; then
            dunstctl set-paused toggle 2>/dev/null || true
            is_paused=$(dunstctl is-paused 2>/dev/null || echo "false")
            if [[ "$is_paused" == "true" ]]; then
                notify-send -a minimal-notif -t 2500 "󰂛  Do Not Disturb" "Notifications are now silenced."
            else
                notify-send -a minimal-notif -t 2500 "󰂚  Notifications Active" "Do Not Disturb has been disabled."
            fi
        fi
        ;;
    *)
        printf 'Usage: %s [dismiss|dismiss-all|restore|dnd]\n' "$0" >&2
        exit 1
        ;;
esac
