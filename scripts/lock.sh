#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
mkdir -p -- "$MINIMAL_RUNTIME" "$MINIMAL_CACHE"

# Wallpaper preparation happens when selecting a wallpaper, never before locking.
# The lock survives exec, so repeated idle/key events cannot open two lockers.
_lock_id="${HYPRLAND_INSTANCE_SIGNATURE:-${WAYLAND_DISPLAY:-default}}"
_lock_id="${_lock_id//[^a-zA-Z0-9_-]/_}"
exec 9>"$MINIMAL_RUNTIME/lock-${_lock_id}.lock"
flock -n 9 || exit 0

# Prevent double-lock race condition if hyprlock is already executing
if pgrep -u "${UID:-$(id -u)}" -x hyprlock >/dev/null 2>&1; then
    exit 0
fi

# Resolve the avatar into our cache without creating files in the home root.
avatar="$MINIMAL_ROOT/wallpapers/default-avatar.png"
for candidate in "/var/lib/AccountsService/icons/${USER:-$(id -un)}" "$HOME/.face" "$HOME/.face.icon"; do
    [[ ! -f $candidate ]] || avatar="$candidate"
done
ln -sf -- "$avatar" "$MINIMAL_CACHE/avatar"

exec hyprlock --grace 0 --config "$MINIMAL_ROOT/hypr/hyprlock.conf" "$@"
