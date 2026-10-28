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
    local vol=""
    if command -v pamixer >/dev/null 2>&1; then
        vol=$(pamixer --get-volume 2>/dev/null) || true
    fi
    if [[ -z "$vol" ]] && command -v wpctl >/dev/null 2>&1; then
        vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print int($2 * 100)}') || true
    fi
    echo "${vol:-0}"
}

is_muted() {
    local state=""
    if command -v pamixer >/dev/null 2>&1; then
        state=$(pamixer --get-mute 2>/dev/null) || true
        if [[ -n "$state" ]]; then
            [[ "$state" == "true" ]]
            return $?
        fi
    fi
    if command -v wpctl >/dev/null 2>&1; then
        wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q '\[MUTED\]'
    else
        return 1
    fi
}

is_mic_muted() {
    local state=""
    if command -v pamixer >/dev/null 2>&1; then
        state=$(pamixer --default-source --get-mute 2>/dev/null) || true
        if [[ -n "$state" ]]; then
            [[ "$state" == "true" ]]
            return $?
        fi
    fi
    if command -v wpctl >/dev/null 2>&1; then
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
        if command -v pamixer >/dev/null 2>&1 && pamixer -i 5 2>/dev/null; then
            :
        elif command -v wpctl >/dev/null 2>&1; then
            wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
        fi
        send_volume_osd
        ;;
    --dec|-d)
        if command -v pamixer >/dev/null 2>&1 && pamixer -d 5 2>/dev/null; then
            :
        elif command -v wpctl >/dev/null 2>&1; then
            wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
        fi
        send_volume_osd
        ;;
    --toggle-mute|-m)
        if command -v pamixer >/dev/null 2>&1 && pamixer -t 2>/dev/null; then
            :
        elif command -v wpctl >/dev/null 2>&1; then
            wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        fi
        send_volume_osd
        ;;
    --toggle-mic-mute|-mic)
        if command -v pamixer >/dev/null 2>&1 && pamixer --default-source -t 2>/dev/null; then
            :
        elif command -v wpctl >/dev/null 2>&1; then
            wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
        fi
        send_mic_osd
        ;;
    --mic-inc)
        if command -v pamixer >/dev/null 2>&1 && pamixer --default-source -i 5 2>/dev/null; then
            :
        elif command -v wpctl >/dev/null 2>&1; then
            wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SOURCE@ 5%+
        fi
        send_mic_osd
        ;;
    --mic-dec)
        if command -v pamixer >/dev/null 2>&1 && pamixer --default-source -d 5 2>/dev/null; then
            :
        elif command -v wpctl >/dev/null 2>&1; then
            wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 5%-
        fi
        send_mic_osd
        ;;
    *)
        echo "Usage: $0 [--inc|--dec|--toggle-mute|--toggle-mic-mute|--mic-inc|--mic-dec]" >&2
        exit 1
        ;;
esac
