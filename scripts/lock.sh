#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — LOCK LAUNCHER
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

# Prevent duplicate hyprlock instances
if pgrep -u "${UID:-$(id -u)}" -x hyprlock >/dev/null 2>&1; then
    exit 0
fi

exec hyprlock --grace 0 --config "$MINIMAL_ROOT/hypr/hyprlock.conf" "$@"
