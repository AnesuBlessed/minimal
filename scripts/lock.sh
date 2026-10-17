#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
mkdir -p -- "$MINIMAL_RUNTIME" "$MINIMAL_CACHE"

# Wallpaper preparation happens when selecting a wallpaper, never before locking.
# The lock survives exec, so repeated idle/key events cannot open two lockers.
exec 9>"$MINIMAL_RUNTIME/lock.lock"
flock -n 9 || exit 0

# Resolve the avatar into our cache without creating files in the home root.
avatar="$MINIMAL_ROOT/wallpapers/default-avatar.png"
[[ ! -f $HOME/.face ]] || avatar="$HOME/.face"
[[ ! -f $HOME/.face.icon ]] || avatar="$HOME/.face.icon"
ln -sf -- "$avatar" "$MINIMAL_CACHE/avatar"

exec hyprlock --grace 0 --config "$MINIMAL_ROOT/hypr/hyprlock.conf" "$@"
