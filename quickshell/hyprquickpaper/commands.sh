#!/usr/bin/env bash
WALL="$1"
if [ -n "$WALL" ] && [ -f "$WALL" ]; then
    awww img "$WALL" -t wipe --transition-angle 30 --transition-step 90
    mkdir -p "$HOME/.config/minimal"
    echo "$WALL" > "$HOME/.config/minimal/current_wallpaper"
    notify-send -a "minimal" -h string:x-canonical-private-synchronous:wallchange "Wallpaper Applied" "$(basename "$WALL")" -t 2000 >/dev/null 2>&1 || true
fi
