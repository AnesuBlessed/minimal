#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — APPLICATION LAUNCHER (DUAL-PANE ROFI)
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
mkdir -p -- "$MINIMAL_STATE"

# Toggle: close if already open
if pgrep -u "$USER" -x rofi >/dev/null 2>&1; then
    pkill -u "$USER" -x rofi
    exit 0
fi

# Ensure wallpaper symlink exists for the banner
if [[ ! -e "$MINIMAL_STATE/wallpaper.set" ]]; then
    if [[ -f "$MINIMAL_STATE/current_wallpaper" ]]; then
        cur_wall=$(cat "$MINIMAL_STATE/current_wallpaper")
        [[ -f "$cur_wall" ]] && ln -sf "$cur_wall" "$MINIMAL_STATE/wallpaper.set"
    fi
    if [[ ! -e "$MINIMAL_STATE/wallpaper.set" ]]; then
        ln -sf "$MINIMAL_ROOT/wallpapers/japan_lake.jpg" "$MINIMAL_STATE/wallpaper.set"
    fi
fi

mode="${1:-drun}"
exec rofi -show "$mode" -theme "$MINIMAL_ROOT/rofi/launcher.rasi"
