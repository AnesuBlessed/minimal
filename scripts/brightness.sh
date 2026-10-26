#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — BRIGHTNESS & DISPLAY OSD CONTROLLER
# =============================================================================
#  Adjusts display brightness via brightnessctl and displays a sleek Mako OSD.
# =============================================================================
set -euo pipefail

get_brightness() {
    if command -v brightnessctl >/dev/null 2>&1; then
        brightnessctl -m | awk -F, '{gsub(/%/,"",$4); print $4}' | head -n1 || echo 100
    else
        echo 100
    fi
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
        brightnessctl set 5%+ >/dev/null 2>&1 || true
        send_brightness_osd
        ;;
    --dec|-d)
        brightnessctl set 5%- >/dev/null 2>&1 || true
        send_brightness_osd
        ;;
    *)
        echo "Usage: $0 [--inc|--dec]" >&2
        exit 1
        ;;
esac
