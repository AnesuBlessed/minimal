#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
mkdir -p -- "$MINIMAL_RUNTIME" "$MINIMAL_CACHE"

# Ensure user avatar exists; fallback to Minimal default avatar
if [[ ! -f $HOME/.face.icon && ! -f $HOME/.face && -f $MINIMAL_ROOT/wallpapers/default-avatar.png ]]; then
    cp -f "$MINIMAL_ROOT/wallpapers/default-avatar.png" "$HOME/.face.icon" 2>/dev/null || true
fi

# Ensure blurred lock image exists
if [[ ! -f $MINIMAL_CACHE/lock.png ]]; then
    wall="$MINIMAL_ROOT/wallpapers/japan_lake.jpg"
    [[ -r $MINIMAL_STATE/current_wallpaper ]] && read -r selected < "$MINIMAL_STATE/current_wallpaper" && [[ -f $selected ]] && wall=$selected
    "$MINIMAL_ROOT/scripts/prepare-lock.sh" "$wall" 2>/dev/null || true
fi

# The lock survives exec, so repeated idle/key events cannot open two lockers.
exec 9>"$MINIMAL_RUNTIME/lock.lock"
flock -n 9 || exit 0
exec hyprlock --grace 0 --config "$MINIMAL_ROOT/hypr/hyprlock.conf" "$@"
