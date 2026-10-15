#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
if [[ ${1:-} == --random ]]; then
    mapfile -d '' -t walls < <(find "$MINIMAL_ROOT/wallpapers" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0)
    ((${#walls[@]})) || { printf 'No wallpapers found\n' >&2; exit 1; }
    exec "$MINIMAL_ROOT/scripts/wallpaper.sh" "${walls[RANDOM % ${#walls[@]}]}"
fi
# Quickshell's own instance selection targets only this configuration.
if quickshell kill -p "$MINIMAL_ROOT/quickshell/hyprquickpaper" >/dev/null 2>&1; then exit 0; fi
export MINIMAL_WALLPAPERS="$MINIMAL_ROOT/wallpapers"
export MINIMAL_THUMBNAILS="$MINIMAL_CACHE/thumbs/"
exec quickshell -n -p "$MINIMAL_ROOT/quickshell/hyprquickpaper"
