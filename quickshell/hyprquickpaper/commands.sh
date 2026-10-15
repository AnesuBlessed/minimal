#!/usr/bin/env bash
WALL="$1"
if [ -n "$WALL" ] && [ -f "$WALL" ]; then
    # Instant visual wipe
    if command -v awww >/dev/null 2>&1; then
        awww img "$WALL" -t wipe --transition-angle 30 --transition-step 90
    fi
    mkdir -p "$HOME/.config/minimal"
    echo "$WALL" > "$HOME/.config/minimal/current_wallpaper"

    # Dynamic Wallbash color generation & instant system palette update
    (
        if command -v hyde-shell >/dev/null 2>&1; then
            hyde-shell wallpaper --set "$WALL" --backend awww --global >/dev/null 2>&1
        fi
        killall -SIGUSR2 waybar 2>/dev/null || true
    ) &

    notify-send -a "minimal" -h string:x-canonical-private-synchronous:wallchange "Wallpaper Applied" "$(basename "$WALL")" -t 2000 >/dev/null 2>&1 || true
fi
