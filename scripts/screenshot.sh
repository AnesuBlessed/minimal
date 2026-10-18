#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

mode=${1:-region}

if [[ $mode == record || $mode == record-full || $mode == status ]]; then
    exec python3 "$MINIMAL_ROOT/scripts/recording.py" "$mode"
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
