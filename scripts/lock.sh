#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — LOCK LAUNCHER
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

# Serialize simultaneous keybind, lid and idle requests.
mkdir -p -m 700 -- "$MINIMAL_RUNTIME"
# Refuse a runtime dir we don't own; failing loudly beats silently not locking.
if [[ ! -O "$MINIMAL_RUNTIME" || -L "$MINIMAL_RUNTIME" ]]; then
    echo "lock.sh: $MINIMAL_RUNTIME is not owned by $(id -un); refusing to use it" >&2
    exec hyprlock --grace 0 --config "$MINIMAL_ROOT/hypr/hyprlock.conf" "$@"
fi
chmod 700 "$MINIMAL_RUNTIME"
exec 9>"$MINIMAL_RUNTIME/lock.lock"
flock -n 9 || exit 0

# Prevent duplicate hyprlock instances
if pgrep -u "${UID:-$(id -u)}" -x hyprlock >/dev/null 2>&1; then
    exit 0
fi

# If hyprlock crashes, the compositor keeps the session locked
# (misc.allow_session_lock_restore); relaunch it so the user can unlock.
for _ in 1 2 3; do
    if hyprlock --grace 0 --config "$MINIMAL_ROOT/hypr/hyprlock.conf" "$@"; then
        exit 0
    fi
    sleep 1
done
# Last resort: hyprlock with its built-in defaults.
exec hyprlock --grace 0
