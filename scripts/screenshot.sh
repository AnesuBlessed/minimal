#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — SCREENSHOT & REGION OCR UTILITY
# =============================================================================
#  Modes:
#    region  - Select rectangle -> copy to clipboard & save
#    full    - Fullscreen capture -> copy to clipboard & save
#    edit    - Select rectangle -> open in Satty/Swappy annotator
#    ocr     - Select rectangle -> extract text via Tesseract to clipboard
# =============================================================================
set -euo pipefail

mode="${1:-region}"
save_dir="${HOME}/Pictures/Screenshots"
mkdir -p -- "$save_dir"
timestamp="$(date +'%Y-%m-%d_%H-%M-%S')"
target_file="${save_dir}/screenshot_${timestamp}.png"

capture=$(mktemp --suffix=.png)
trap 'rm -f -- "$capture"' EXIT

case "$mode" in
    region|edit|ocr)
        region=$(slurp -b "#0f1a2ab3" -c "#ca9ee6ff" -w 2 2>/dev/null) || exit 0
        [[ -n "$region" ]] || exit 0
        grim -g "$region" "$capture"
        ;;
    full)
        grim "$capture"
        ;;
    *)
        echo "Usage: $0 [region|full|edit|ocr]" >&2
        exit 2
        ;;
esac

[[ -s "$capture" ]] || exit 1

case "$mode" in
    ocr)
        if ! command -v tesseract >/dev/null 2>&1; then
            notify-send -a minimal -u low -- "OCR unavailable" "tesseract is not installed." 2>/dev/null || true
            exit 1
        fi
        text=$(tesseract "$capture" stdout 2>/dev/null | sed -e 's/[[:space:]]*$//') || true
        if [[ -z "${text//[[:space:]]/}" ]]; then
            notify-send -a minimal -u low -- "OCR" "No text detected in selected region." 2>/dev/null || true
            exit 0
        fi
        printf '%s' "$text" | wl-copy
        notify-send -a minimal -t 2000 -- "OCR Copied" "${text:0:80}" 2>/dev/null || true
        ;;
    edit)
        if command -v satty >/dev/null 2>&1; then
            satty --filename "$capture" --fullscreen --output-filename "$target_file"
        elif command -v swappy >/dev/null 2>&1; then
            swappy -f "$capture" -o "$target_file"
        else
            cp -- "$capture" "$target_file"
            wl-copy --type image/png < "$capture"
            notify-send -a minimal -t 2000 -- "Screenshot" "Saved to Screenshots & copied to clipboard" 2>/dev/null || true
        fi
        ;;
    region|full)
        cp -- "$capture" "$target_file"
        wl-copy --type image/png < "$capture"
        notify-send -a minimal -t 2000 -i "$target_file" -- "Screenshot" "Copied to clipboard and saved to Pictures/Screenshots" 2>/dev/null || true
        ;;
esac
