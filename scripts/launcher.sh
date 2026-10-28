#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — APPLICATION LAUNCHER (DUAL-PANE ROFI)
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
mkdir -p -- "$MINIMAL_STATE"

# Toggle: close launcher if already open; switch if another rofi is open
uid="${UID:-$(id -u)}"
if pgrep -u "$uid" -f "rofi.*launcher\.rasi" >/dev/null 2>&1; then
    pkill -u "$uid" -f "rofi.*launcher\.rasi"
    exit 0
fi
pkill -u "$uid" -x rofi 2>/dev/null || true

banner=$(python3 "$MINIMAL_ROOT/scripts/rofi-banner.py" launcher)

mode="${1:-drun}"
exec rofi -show "$mode" -theme "$MINIMAL_ROOT/rofi/launcher.rasi" -theme-str "$banner"
