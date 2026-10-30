#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — BRIGHTNESS & DISPLAY OSD CONTROLLER
# =============================================================================
#  Adjusts display brightness via brightnessctl and displays a sleek Mako OSD.
# =============================================================================
set -euo pipefail

get_brightness() {
    brightnessctl --class=backlight --machine-readable info |
        awk -F, 'NR == 1 {gsub(/%/,"",$4); print $4}'
}

send_brightness_osd() {
    local val
    val=$(get_brightness)
    local icon="display-brightness-symbolic"

    if ((val < 35)); then
        icon="display-brightness-low-symbolic"
    elif ((val < 70)); then
        icon="display-brightness-medium-symbolic"
    else
        icon="display-brightness-high-symbolic"
    fi

    notify-send -a "minimal" \
        -u low \
        -t 1400 \
        -h string:x-canonical-private-synchronous:brightness_osd \
        -h int:value:"$val" \
        -i "$icon" \
        "Brightness" "Level: ${val}%" 2>/dev/null || true
}

case "${1:-}" in
    --inc|-i)
        adjustment=5%+
        ;;
    --dec|-d)
        adjustment=5%-
        ;;
    *)
        echo "Usage: $0 [--inc|--dec]" >&2
        exit 1
        ;;
esac

if ! command -v brightnessctl >/dev/null 2>&1; then
    echo "Brightness unavailable: install brightnessctl." >&2
    notify-send -a minimal -- "Brightness unavailable" "Install brightnessctl." 2>/dev/null || true
    exit 1
fi

if ! error=$(brightnessctl --class=backlight --min-value=1 set "$adjustment" 2>&1); then
    printf 'Brightness adjustment failed: %s\n' "$error" >&2
    notify-send -a minimal -- "Brightness adjustment failed" "$error" 2>/dev/null || true
    exit 1
fi
send_brightness_osd
