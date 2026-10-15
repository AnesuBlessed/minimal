#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
mkdir -p -- "$MINIMAL_RUNTIME"
# The lock survives exec, so repeated idle/key events cannot open two lockers.
exec 9>"$MINIMAL_RUNTIME/lock.lock"
flock -n 9 || exit 0
exec hyprlock --grace 0 --config "$MINIMAL_ROOT/hypr/hyprlock.conf" "$@"
