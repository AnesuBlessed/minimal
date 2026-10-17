#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

mode=${1:-region}

if [[ $mode == record || $mode == record-full ]]; then
    mkdir -p -- "$MINIMAL_RUNTIME"
    pidfile="$MINIMAL_RUNTIME/recording.pid"
    if [[ -r $pidfile ]]; then
        { read -r rec_pid rec_start _ || true; read -r rec_out || true; } < "$pidfile"
        if [[ ${rec_pid:-} =~ ^[0-9]+$ && -r /proc/$rec_pid/stat ]]; then
            cur_start=$(awk '{sub(/^.*\)[[:space:]]+/, ""); print $20}' "/proc/$rec_pid/stat")
            if [[ -z ${rec_start:-} || $cur_start == "$rec_start" ]]; then
                kill -INT "$rec_pid" 2>/dev/null || true
                rm -f -- "$pidfile"
                pkill -RTMIN+9 waybar 2>/dev/null || true
                notify-send -a minimal -u low "Screen recording saved" "${rec_out:-Recording stopped}" 2>/dev/null || true
                exit 0
            fi
        fi
        rm -f -- "$pidfile"
    fi

    recorder=""
    for candidate in wl-screenrec wf-recorder; do
        if command -v "$candidate" >/dev/null 2>&1; then
            recorder=$candidate
            break
        fi
    done
    if [[ -z $recorder ]]; then
        notify-send -a minimal -u low "Screen recorder unavailable" "Install wl-screenrec or wf-recorder." 2>/dev/null || true
        exit 0
    fi

    rec_args=()
    if [[ $mode == record ]]; then
        region=$(slurp) || exit 0
        [[ -n $region ]] || exit 0
        rec_args=(-g "$region")
    fi

    out_dir="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"
    mkdir -p -- "$out_dir"
    out_file="$out_dir/recording-$(date +%Y%m%d-%H%M%S).mp4"
    "$recorder" "${rec_args[@]}" -f "$out_file" >/dev/null 2>&1 &
    rec_pid=$!
    rec_start=""
    if [[ -r /proc/$rec_pid/stat ]]; then
        rec_start=$(awk '{sub(/^.*\)[[:space:]]+/, ""); print $20}' "/proc/$rec_pid/stat")
    fi
    printf '%s %s %s\n%s\n' "$rec_pid" "$rec_start" "$(date +%s)" "$out_file" > "$pidfile"
    pkill -RTMIN+9 waybar 2>/dev/null || true
    notify-send -a minimal -u low "Recording started" "Press Super+Shift+R or click Notch to stop." 2>/dev/null || true
    exit 0
fi

case $mode in
    region|edit|ocr) region=$(slurp) || exit 0; [[ -n $region ]] || exit 0; args=(-g "$region");;
    full) args=();;
    *) exit 2;;
esac
capture=$(mktemp --suffix=.png)
trap 'rm -f -- "$capture"' EXIT
grim "${args[@]}" "$capture"
[[ -s $capture ]] || exit 1
if [[ $mode == ocr ]]; then
    if ! command -v tesseract >/dev/null 2>&1; then
        notify-send -a minimal -u low "OCR unavailable" "Install tesseract to extract text from screen regions." 2>/dev/null || true
        exit 0
    fi
    text=$(tesseract "$capture" stdout 2>/dev/null | sed -e 's/[[:space:]]*$//') || true
    if [[ -z ${text//[[:space:]]/} ]]; then
        notify-send -a minimal -u low "OCR: No text detected" "Try selecting a clearer region." 2>/dev/null || true
        exit 0
    fi
    printf '%s' "$text" | wl-copy
    notify-send -a minimal -u low "OCR copied to clipboard" "${text:0:120}" 2>/dev/null || true
elif [[ $mode == edit ]]; then
    if command -v satty >/dev/null 2>&1; then
        satty --filename "$capture" --fullscreen
    else
        wl-copy --type image/png < "$capture"
        notify-send -a minimal -u low "Screenshot copied" "Install satty for annotation mode." 2>/dev/null || true
    fi
else
    wl-copy --type image/png < "$capture"
fi
