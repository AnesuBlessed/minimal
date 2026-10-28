#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — CLIPBOARD MANAGER (WAYBAR DROPDOWN ROFI)
# =============================================================================
#  Features:
#    - Left-click / Default: Dropdown under Waybar, wallpaper banner, clean text
#    - Right-click / --delete: Brush icon wipe all at top, [ ✕ ] on every clip
#    - Middle-click / --wipe: Instant confirmation wipe
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

ROFI_THEME="$MINIMAL_ROOT/rofi/clipboard.rasi"
placement=$(python3 "$MINIMAL_ROOT/scripts/clipboard-placement.py")
ROFI_CONFIRM="$MINIMAL_ROOT/rofi/selector.rasi"
WIPE_TAG="󰃢  Clear All History (Wipe)"

# Toggle: close clipboard if already open; switch if another rofi is open
uid="${UID:-$(id -u)}"
if pgrep -u "$uid" -f "rofi.*clipboard\.rasi" >/dev/null 2>&1; then
    pkill -u "$uid" -f "rofi.*clipboard\.rasi"
    exit 0
fi
pkill -u "$uid" -x rofi 2>/dev/null || true

banner=$(python3 "$MINIMAL_ROOT/scripts/rofi-banner.py" clipboard)

case "${1:-}" in
    --wipe)
        confirm=$(printf '󰃢  Yes, Clear All History\n󰜺  No, Cancel' | rofi -dmenu -no-custom -theme "$ROFI_CONFIRM" -p "☢ Confirm Wipe: " 2>/dev/null) || exit 0
        if [[ "$confirm" == *"Yes"* ]]; then
            cliphist wipe
            notify-send -a minimal -t 1500 -i edit-clear -- "Clipboard" "History wiped" 2>/dev/null || true
        fi
        exit 0
        ;;

    --delete|-d)
        # Delete mode: top wipe action + 'x' tag on every clip
        selected=$(
            {
                printf "%s\t%s\n" "0" "$WIPE_TAG"
                while IFS=$'\t' read -r id val; do
                    [[ -n "$id" ]] || continue
                    printf "%s\t[ ✕ ]  %s\n" "$id" "$val"
                done < <(cliphist list 2>/dev/null || true)
            } | rofi -dmenu -no-custom -display-columns 2 -theme "$ROFI_THEME" -theme-str "$placement $banner entry { placeholder: \"Select entry to delete...\"; }" 2>/dev/null
        ) || exit 0

        [[ -n "$selected" ]] || exit 0

        clip_id="${selected%%$'\t'*}"
        if [[ "$clip_id" == "0" ]]; then
            "$0" --wipe
            exit 0
        fi
        match_line=$(cliphist list 2>/dev/null | grep -m1 "^${clip_id}"$'\t' || true)
        if [[ -n "$match_line" ]]; then
            printf '%s\n' "$match_line" | cliphist delete
            notify-send -a minimal -t 1200 -i edit-delete -- "Clipboard" "Entry deleted" 2>/dev/null || true
        fi
        ;;

    *)
        # Default Mode: Clean raw text, no icons, wallpaper banner
        selected=$(cliphist list 2>/dev/null | rofi -dmenu -no-custom -display-columns 2 -theme "$ROFI_THEME" -theme-str "$placement $banner" 2>/dev/null) || exit 0
        [[ -n "$selected" ]] || exit 0

        printf '%s\n' "$selected" | cliphist decode | wl-copy
        notify-send -a minimal -t 1200 -i edit-copy -- "Clipboard" "Copied to clipboard" 2>/dev/null || true
        ;;
esac
