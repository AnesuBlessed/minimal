#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — WALLPAPER CHANGER & CAROUSEL LAUNCHER
# =============================================================================
#  - Default: Launches native 3D Quickshell Cover-Flow Carousel (0 MB daemon)
#  - Pass '--random' for instantaneous random switch without opening UI
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "$1" == "--random" ]; then
    WALLS=($(find "$PROJECT_DIR/wallpapers" -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.webp" \) 2>/dev/null))
    if [ ${#WALLS[@]} -gt 0 ]; then
        CHOSEN="${WALLS[$RANDOM % ${#WALLS[@]}]}"
        if command -v awww >/dev/null 2>&1; then
            awww img "$CHOSEN" -t wipe --transition-angle 30 --transition-step 90
        fi
        mkdir -p "$HOME/.config/minimal"
        echo "$CHOSEN" > "$HOME/.config/minimal/current_wallpaper"
        notify-send -a "minimal" -h string:x-canonical-private-synchronous:wallchange "Wallpaper Switched" "$(basename "$CHOSEN")" -t 2000 >/dev/null 2>&1 || true
    fi
    exit 0
fi

# Toggle off if already open
if pkill -x quickshell 2>/dev/null; then
    exit 0
fi

# Launch standalone 3D Quickshell Carousel
if command -v quickshell >/dev/null 2>&1; then
    exec quickshell -p "$PROJECT_DIR/quickshell/hyprquickpaper"
else
    notify-send -a "minimal" "Quickshell Missing" "Run: sudo pacman -S quickshell" -t 4000
    echo "Quickshell is not installed. Please run: sudo pacman -S --needed quickshell"
    exit 1
fi
