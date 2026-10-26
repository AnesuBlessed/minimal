#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — FAST WALLPAPER CHANGER & PICKER
# =============================================================================
#  Usage:
#    wallpaper.sh <path/to/image>
#    wallpaper.sh --random
#    wallpaper.sh --menu
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
mkdir -p -- "$MINIMAL_STATE"

# Build deduplicated map of available wallpapers (by basename)
declare -A wall_map
choices=()

while IFS= read -r file; do
    [[ -n "$file" && -f "$file" ]] || continue
    base="$(basename "$file")"
    if [[ -z "${wall_map["$base"]:-}" ]]; then
        wall_map["$base"]="$file"
        choices+=("$base")
    fi
done < <(find "$MINIMAL_ROOT/wallpapers" "${HOME}/Pictures/Wallpapers" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) 2>/dev/null | sort -u)

wall=""

case "${1:-}" in
    --random)
        if ((${#choices[@]} > 0)); then
            rand_idx=$((RANDOM % ${#choices[@]}))
            rand_base="${choices[$rand_idx]}"
            wall="${wall_map["$rand_base"]}"
        fi
        ;;
    --menu)
        if ((${#choices[@]} > 0)); then
            selected_name=$(printf '%s\n' "${choices[@]}" | rofi -dmenu -theme "$MINIMAL_ROOT/rofi/selector.rasi" -p "󰸉 Wallpaper") || exit 0
            [[ -n "$selected_name" ]] || exit 0
            wall="${wall_map["$selected_name"]:-}"
        fi
        ;;
    *)
        if [[ -n "${1:-}" && -f "$1" ]]; then
            wall="$(realpath "$1")"
        elif [[ -f "$MINIMAL_STATE/current_wallpaper" ]]; then
            wall="$(cat "$MINIMAL_STATE/current_wallpaper")"
        elif ((${#choices[@]} > 0)); then
            wall="${wall_map["${choices[0]}"]}"
        else
            wall="$MINIMAL_ROOT/wallpapers/japan_lake.jpg"
        fi
        ;;
esac

[[ -n "$wall" && -f "$wall" ]] || exit 1

# Apply via Hyprpaper IPC cleanly
if pgrep -x hyprpaper >/dev/null 2>&1; then
    hyprctl hyprpaper preload "$wall" >/dev/null 2>&1 || true
    hyprctl hyprpaper wallpaper ",$wall,cover" >/dev/null 2>&1 || hyprctl hyprpaper wallpaper ",$wall" >/dev/null 2>&1 || true
fi

printf '%s\n' "$wall" > "$MINIMAL_STATE/current_wallpaper"
ln -sf "$wall" "$MINIMAL_STATE/wallpaper.set"
pkill -RTMIN+19 waybar 2>/dev/null || true
notify-send -a minimal -t 1500 -i "preferences-desktop-wallpaper" -- "Wallpaper" "$(basename "$wall")" 2>/dev/null || true
