#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

CONFIG_PATH="$MINIMAL_ROOT/quickshell/wallpaper-picker/shell.qml"
CONFIG_DIR="$MINIMAL_ROOT/quickshell/wallpaper-picker"

cycle_next_wallpaper() {
    mapfile -d '' -t walls < <(find "$MINIMAL_ROOT/wallpapers" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0 | sort -z)
    ((${#walls[@]})) || { printf 'No wallpapers found\n' >&2; exit 1; }
    
    current=""
    if [[ -r "$MINIMAL_STATE/current_wallpaper" ]]; then
        current=$(<"$MINIMAL_STATE/current_wallpaper")
    fi
    
    next_idx=0
    for idx in "${!walls[@]}"; do
        if [[ "${walls[idx]}" == "$current" ]]; then
            next_idx=$(( (idx + 1) % ${#walls[@]} ))
            break
        fi
    done
    exec "$MINIMAL_ROOT/scripts/wallpaper.sh" "${walls[next_idx]}"
}

if [[ ${1:-} == --random ]]; then
    mapfile -d '' -t walls < <(find "$MINIMAL_ROOT/wallpapers" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0)
    ((${#walls[@]})) || { printf 'No wallpapers found\n' >&2; exit 1; }
    exec "$MINIMAL_ROOT/scripts/wallpaper.sh" "${walls[RANDOM % ${#walls[@]}]}"
fi

# Fallback immediately to next wallpaper if quickshell is not available
if ! command -v quickshell >/dev/null 2>&1; then
    cycle_next_wallpaper
fi

# Quickshell toggle: if already running the wallpaper picker, close it.
if quickshell kill -p "$CONFIG_PATH" >/dev/null 2>&1 || quickshell kill -p "$CONFIG_DIR" >/dev/null 2>&1; then
    exit 0
fi

export MINIMAL_WALLPAPERS="$MINIMAL_ROOT/wallpapers"
export MINIMAL_THUMBNAILS="$MINIMAL_CACHE/wallpaper-picker/thumbs"
export QS_CACHE_WALLPAPER_PICKER="$MINIMAL_CACHE/wallpaper-picker"
export QS_RUN_WALLPAPER_PICKER="$MINIMAL_RUNTIME/wallpaper-picker"

exec quickshell -n -p "$CONFIG_PATH"
