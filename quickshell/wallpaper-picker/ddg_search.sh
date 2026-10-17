#!/usr/bin/env bash
set -eo pipefail

QUERY="$1"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
MINIMAL_ROOT="${MINIMAL_ROOT:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

if [ -f "$MINIMAL_ROOT/scripts/paths.sh" ]; then
    source "$MINIMAL_ROOT/scripts/paths.sh"
fi

MINIMAL_CACHE="${MINIMAL_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/minimal}"
MINIMAL_RUNTIME="${MINIMAL_RUNTIME:-${XDG_RUNTIME_DIR:-$MINIMAL_CACHE}/minimal}"

CACHE_DIR="${QS_CACHE_WALLPAPER_PICKER:-$MINIMAL_CACHE/wallpaper-picker}"
RUN_DIR="${QS_RUN_WALLPAPER_PICKER:-$MINIMAL_RUNTIME/wallpaper-picker}"
LOG_DIR="${QS_LOG_DIR:-$RUN_DIR/logs}"

SEARCH_DIR="$CACHE_DIR/search_thumbs"
MAP_FILE="$CACHE_DIR/search_map.txt"
CONTROL_FILE="$RUN_DIR/ddg_search_control"
LOG_FILE="$LOG_DIR/ddg_downloader.log"

export MINIMAL_ROOT MINIMAL_CACHE MINIMAL_RUNTIME QS_CACHE_WALLPAPER_PICKER="$CACHE_DIR" QS_RUN_WALLPAPER_PICKER="$RUN_DIR" QS_LOG_DIR="$LOG_DIR"
mkdir -p "$SEARCH_DIR" "$RUN_DIR" "$LOG_DIR"

echo "=== Starting search for: $QUERY ===" > "$LOG_FILE"

# Guarantee directory exists
mkdir -p "$SEARCH_DIR"

# The Pipe: Python provides links, OS provides backpressure
python3 -u "$SCRIPT_DIR/get_ddg_links.py" "$QUERY" | while IFS='|' read -r thumb_url full_url; do
    
    # Safely read control file
    state=$(cat "$CONTROL_FILE" 2>/dev/null | tr -d '[:space:]')
    
    if [[ "$state" == "stop" ]]; then 
        echo "Stop signal received. Exiting." >> "$LOG_FILE"
        exit 0 
    fi
    
    while [[ "$state" == "pause" ]]; do
        # Block on a file event; the timeout is only a safety net.
        if command -v inotifywait >/dev/null 2>&1; then
            inotifywait -q -t 30 -e close_write,moved_to,create "$RUN_DIR" >/dev/null 2>&1 || true
        else
            sleep 5
        fi
        state=$(cat "$CONTROL_FILE" 2>/dev/null | tr -d '[:space:]')
    done

    if [[ "$state" == "stop" ]]; then
        echo "Stop signal received after pause. Exiting." >> "$LOG_FILE"
        exit 0
    fi

    if [ -z "$thumb_url" ] || [ -z "$full_url" ]; then continue; fi

    [[ $thumb_url == https://* || $thumb_url == http://* ]] || continue
    [[ $full_url == https://* || $full_url == http://* ]] || continue
    # =========================================================================
    # PRE-FLIGHT CHECK ON THE FULL URL
    # =========================================================================
    target_headers=$(curl --proto '=http,https' --proto-redir '=http,https' -s -I -L -m 3 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "$full_url" 2>/dev/null || true)
    target_type=$(echo "$target_headers" | grep -i "content-type:" | tail -n 1 | tr -d '\r')

    if [[ ! "$target_type" =~ "image/" ]]; then
        echo "Skip: Full URL is dead or HTML ($target_type) -> $full_url" >> "$LOG_FILE"
        continue
    fi
    # =========================================================================

    uuid="$(date +%s%N)_$$_${RANDOM}"
    filename="ddg_${uuid}.png"
    filepath="$SEARCH_DIR/$filename"
    tmppath="${filepath}.tmp"

    echo "Downloading Thumb: $thumb_url -> $filename" >> "$LOG_FILE"

    # Timeout -m 5 prevents freezing on stalled connections
    curl --proto '=http,https' --proto-redir '=http,https' --max-filesize 8388608 --fail -s -L -m 5 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" "$thumb_url" -o "$tmppath" 2>/dev/null || true

    # Check state again AFTER the curl block
    state=$(cat "$CONTROL_FILE" 2>/dev/null | tr -d '[:space:]')
    if [[ "$state" == "stop" ]]; then 
        echo "Stop signal received during download. Discarding." >> "$LOG_FILE"
        rm -f "$tmppath"
        exit 0 
    fi

    # Decode only recognized, bounded rasters; publish a normalized static PNG.
    if "$MINIMAL_ROOT/scripts/image-preview.py" "$tmppath" "$filepath" 2>>"$LOG_FILE"; then
        printf '%s|%s\n' "$filename" "$full_url" >> "$MAP_FILE"
    fi
    rm -f -- "$tmppath"

done

echo "=== Pipeline finished ===" >> "$LOG_FILE"
