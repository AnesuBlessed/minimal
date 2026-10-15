#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
MINIMAL_ROOT="${MINIMAL_ROOT:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

if [ -f "$MINIMAL_ROOT/scripts/paths.sh" ]; then
    source "$MINIMAL_ROOT/scripts/paths.sh"
fi

MINIMAL_CACHE="${MINIMAL_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/minimal}"
MINIMAL_RUNTIME="${MINIMAL_RUNTIME:-${XDG_RUNTIME_DIR:-$MINIMAL_CACHE}/minimal}"

SRC_DIR="${MINIMAL_WALLPAPERS:-${WALLPAPER_DIR:-$MINIMAL_ROOT/wallpapers}}"
CACHE_DIR="${QS_CACHE_WALLPAPER_PICKER:-$MINIMAL_CACHE/wallpaper-picker}"
THUMB_DIR="$CACHE_DIR/thumbs"
COLOR_DIR="$CACHE_DIR/colors_markers"
RUN_DIR="${QS_RUN_WALLPAPER_PICKER:-$MINIMAL_RUNTIME/wallpaper-picker}"
PREP_LOCK="$RUN_DIR/wallpaper_prep.lock"
LOG_FILE="$RUN_DIR/logs/prep.log"

mkdir -p "$THUMB_DIR" "$COLOR_DIR" "$RUN_DIR" "$RUN_DIR/logs"

# Ensure single instance
if [ -f "$PREP_LOCK" ]; then
    pid=$(cat "$PREP_LOCK" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        exit 0
    fi
fi
echo "$BASHPID" > "$PREP_LOCK"
trap 'rm -f "$PREP_LOCK"' EXIT

echo "=== Wallpaper thumbnail & color marker generation started $(date) ===" > "$LOG_FILE"

# Determine commands
MAGICK_CMD=""
if command -v magick &>/dev/null; then
    MAGICK_CMD="magick"
elif command -v convert &>/dev/null; then
    MAGICK_CMD="convert"
fi

FFMPEG_CMD=""
if command -v ffmpeg &>/dev/null; then
    FFMPEG_CMD="ffmpeg"
fi

# Process wallpapers
active_jobs=0
max_jobs=4

# Process files
find "$SRC_DIR" -maxdepth 1 -type f \( \
    -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
    -o -iname "*.webp" -o -iname "*.gif" -o -iname "*.mp4" \
    -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.webm" \) | while read -r img; do

    (
        filename=$(basename "$img")
        extension="${filename##*.}"
        ext_lower=$(echo "$extension" | tr '[:upper:]' '[:lower:]')

        is_video=0
        if [[ "$ext_lower" =~ ^(mp4|mkv|mov|webm)$ ]]; then
            is_video=1
        fi

        target_name="$filename"
        if [ $is_video -eq 1 ]; then
            target_name="000_$filename"
        fi
        thumb="$THUMB_DIR/$target_name"

        # 1. Generate thumbnail if needed
        if [ ! -f "$thumb" ] || [ "$img" -nt "$thumb" ]; then
            if [ $is_video -eq 1 ]; then
                if [ -n "$FFMPEG_CMD" ]; then
                    $FFMPEG_CMD -y -ss 00:00:05 -i "$img" -vframes 1 -threads 1 -f image2 -q:v 2 "$thumb.tmp.jpg" >/dev/null 2>&1 || \
                    $FFMPEG_CMD -y -ss 00:00:01 -i "$img" -vframes 1 -threads 1 -f image2 -q:v 2 "$thumb.tmp.jpg" >/dev/null 2>&1 || true
                    if [ -f "$thumb.tmp.jpg" ]; then
                        mv -f "$thumb.tmp.jpg" "$thumb"
                    fi
                fi
            else
                if [ -n "$MAGICK_CMD" ]; then
                    if [ "$ext_lower" = "png" ]; then
                        $MAGICK_CMD "$img" -resize x420 "$thumb.tmp.png" 2>/dev/null && mv -f "$thumb.tmp.png" "$thumb" || true
                    elif [ "$ext_lower" = "webp" ]; then
                        $MAGICK_CMD "$img" -resize x420 -quality 75 "$thumb.tmp.webp" 2>/dev/null && mv -f "$thumb.tmp.webp" "$thumb" || true
                    else
                        $MAGICK_CMD "$img" -resize x420 -quality 75 "$thumb.tmp.jpg" 2>/dev/null && mv -f "$thumb.tmp.jpg" "$thumb" || true
                    fi
                fi
            fi
        fi

        # 2. Generate dominant color marker if thumb exists
        if [ -f "$thumb" ]; then
            found=0
            for marker in "$COLOR_DIR/${target_name}_HEX_"*; do
                if [ -e "$marker" ]; then
                    found=1
                    break
                fi
            done

            if [ $found -eq 0 ] && [ -n "$MAGICK_CMD" ]; then
                hex=$($MAGICK_CMD "$thumb" -modulate 100,200 -resize "1x1^" -gravity center -extent 1x1 -depth 8 -format "%[hex:p{0,0}]" info:- 2>/dev/null | grep -oE '[0-9A-Fa-f]{6}' | head -n 1)
                if [ -n "$hex" ]; then
                    touch "$COLOR_DIR/${target_name}_HEX_${hex}"
                fi
            fi
        fi
    ) &

    active_jobs=$((active_jobs + 1))
    if [ "$active_jobs" -ge "$max_jobs" ]; then
        wait -n 2>/dev/null || true
        active_jobs=$((active_jobs - 1))
    fi
done

wait
echo "=== Generation finished $(date) ===" >> "$LOG_FILE"
