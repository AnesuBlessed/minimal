#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — AUDIO & VOLUME OSD CONTROLLER
# =============================================================================
#  Provides volume/mic control with smooth Mako progress-bar OSD.
#  Prefers pamixer for robust sink fallback (e.g. disconnected bluetooth),
#  with wpctl as a reliable secondary fallback.
# =============================================================================
set -euo pipefail

get_volume() {
    if command -v pamixer >/dev/null 2>&1; then
        pamixer --get-volume 2>/dev/null || echo 0
    elif command -v wpctl >/dev/null 2>&1; then
        wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print int($2 * 100)}' || echo 0
    else
        echo 50
    fi
}

is_muted() {
    if command -v pamixer >/dev/null 2>&1; then
        [[ "$(pamixer --get-mute 2>/dev/null)" == "true" ]]
    elif command -v wpctl >/dev/null 2>&1; then
        wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q '\[MUTED\]'
    else
        return 1
    fi
}

is_mic_muted() {
    if command -v pamixer >/dev/null 2>&1; then
        [[ "$(pamixer --default-source --get-mute 2>/dev/null)" == "true" ]]
    elif command -v wpctl >/dev/null 2>&1; then
        wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q '\[MUTED\]'
    else
        return 1
    fi
}

send_volume_osd() {
    local vol
    vol=$(get_volume)
    local icon
    local status="Volume: ${vol}%"

    if is_muted || ((vol == 0)); then
        icon="audio-volume-muted"
        status="Volume: Muted"
        vol=0
    elif ((vol < 35)); then
        icon="audio-volume-low"
    elif ((vol < 70)); then
        icon="audio-volume-medium"
    else
        icon="audio-volume-high"
    fi

    notify-send -a "minimal" \
        -u low \
        -t 1400 \
        -h string:x-canonical-private-synchronous:audio_osd \
        -h int:value:"$vol" \
        -i "$icon" \
        "Audio" "$status" 2>/dev/null || true
}

send_mic_osd() {
    local icon="audio-input-microphone"
    local status="Microphone: Active"

    if is_mic_muted; then
        icon="microphone-sensitivity-muted"
        status="Microphone: Muted"
    fi

    notify-send -a "minimal" \
        -u low \
        -t 1400 \
        -h string:x-canonical-private-synchronous:mic_osd \
        -i "$icon" \
        "Microphone" "$status" 2>/dev/null || true
}

case "${1:-}" in
    --inc|-i)
        if command -v pamixer >/dev/null 2>&1; then
            pamixer -i 5 --allow-boost=false 2>/dev/null || true
        else
            wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ 2>/dev/null || true
        fi
        send_volume_osd
        ;;
    --dec|-d)
        if command -v pamixer >/dev/null 2>&1; then
            pamixer -d 5 2>/dev/null || true
        else
            wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- 2>/dev/null || true
        fi
        send_volume_osd
        ;;
    --toggle-mute|-m)
        if command -v pamixer >/dev/null 2>&1; then
            pamixer -t 2>/dev/null || true
        else
            wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle 2>/dev/null || true
        fi
        send_volume_osd
        ;;
    --toggle-mic-mute|-mic)
        if command -v pamixer >/dev/null 2>&1; then
            pamixer --default-source -t 2>/dev/null || true
        else
            wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle 2>/dev/null || true
        fi
        send_mic_osd
        ;;
    --mic-inc)
        if command -v pamixer >/dev/null 2>&1; then
            pamixer --default-source -i 5 --allow-boost=false 2>/dev/null || true
        else
            wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SOURCE@ 5%+ 2>/dev/null || true
        fi
        send_mic_osd
        ;;
    --mic-dec)
        if command -v pamixer >/dev/null 2>&1; then
            pamixer --default-source -d 5 2>/dev/null || true
        else
            wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 5%- 2>/dev/null || true
        fi
        send_mic_osd
        ;;
    *)
        echo "Usage: $0 [--inc|--dec|--toggle-mute|--toggle-mic-mute|--mic-inc|--mic-dec]" >&2
        exit 1
        ;;
esac
