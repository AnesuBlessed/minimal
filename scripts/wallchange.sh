#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

CONFIG_PATH="$MINIMAL_ROOT/quickshell/wallpaper-picker/shell.qml"

cycle_next_wallpaper() {
    mapfile -d '' -t walls < <(find "$MINIMAL_ROOT/wallpapers" -maxdepth 1 -type f ! -name default-avatar.png \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0 | sort -z)
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
    mapfile -d '' -t walls < <(find "$MINIMAL_ROOT/wallpapers" -maxdepth 1 -type f ! -name default-avatar.png \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0)
    ((${#walls[@]})) || { printf 'No wallpapers found\n' >&2; exit 1; }
    exec "$MINIMAL_ROOT/scripts/wallpaper.sh" "${walls[RANDOM % ${#walls[@]}]}"
fi

# Fallback immediately to next wallpaper if quickshell is not available
if ! command -v quickshell >/dev/null 2>&1; then
    cycle_next_wallpaper
fi

mkdir -p -- "$MINIMAL_RUNTIME"
exec 9>"$MINIMAL_RUNTIME/wallpaper-toggle.lock"
flock -n 9 || exit 0

# Fast PID-tracked toggle if managed by popup.sh; fallback to quickshell kill -p if started directly.
if [[ ! -r "$MINIMAL_RUNTIME/wallpaper-picker.pid" ]] && pgrep -u "${UID:-$(id -u)}" -x quickshell >/dev/null 2>&1 && quickshell kill -p "$CONFIG_PATH" >/dev/null 2>&1; then
    exit 0
fi

export MINIMAL_WALLPAPERS="$MINIMAL_ROOT/wallpapers"
export MINIMAL_THUMBNAILS="$MINIMAL_CACHE/wallpaper-picker/thumbs"
export QS_CACHE_WALLPAPER_PICKER="$MINIMAL_CACHE/wallpaper-picker"
export QS_RUN_WALLPAPER_PICKER="$MINIMAL_RUNTIME/wallpaper-picker"
if [[ -r "$MINIMAL_STATE/current_wallpaper" ]]; then
    cur_wall=$(<"$MINIMAL_STATE/current_wallpaper")
    export MINIMAL_CURRENT_WALLPAPER="${cur_wall##*/}"
fi

MINIMAL_POPUP_OUTPUT=$(hyprctl -j monitors 2>/dev/null | jq -r 'first(.[] | select(.focused)).name // empty' || true)
export MINIMAL_POPUP_OUTPUT
exec "$MINIMAL_ROOT/scripts/popup.sh" wallpaper-picker quickshell -n -p "$CONFIG_PATH" 9>&-
