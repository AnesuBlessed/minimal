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
            selected_name=$(printf '%s\n' "${choices[@]}" | rofi -dmenu -no-custom -theme "$MINIMAL_ROOT/rofi/selector.rasi" -p "󰸉 Wallpaper") || exit 0
            [[ -n "$selected_name" ]] || exit 0
            wall="${wall_map["$selected_name"]:-}"
        fi
        ;;
    *)
        if [[ -n "${1:-}" && -f "$1" ]]; then
            wall="$(realpath "$1")"
        elif [[ -f "$MINIMAL_STATE/current_wallpaper" ]] && [[ -f "$(< "$MINIMAL_STATE/current_wallpaper")" ]]; then
            wall="$(< "$MINIMAL_STATE/current_wallpaper")"
        elif [[ -f "$MINIMAL_ROOT/wallpapers/japan_lake.jpg" ]]; then
            wall="$MINIMAL_ROOT/wallpapers/japan_lake.jpg"
        elif ((${#choices[@]} > 0)); then
            wall="${wall_map["${choices[0]}"]}"
        fi
        ;;
esac

[[ -n "$wall" && -f "$wall" ]] || exit 1

# Hyprpaper 0.8+: apply to all outputs, then persist only a successful change.
# https://wiki.hypr.land/Hypr-Ecosystem/hyprpaper/
if [[ "$wall" == *','* ]]; then
    echo "Hyprpaper IPC cannot represent wallpaper paths containing commas" >&2
    exit 1
fi
applied=false
for attempt in {1..10}; do
    if response=$(hyprctl hyprpaper wallpaper ",$wall,cover" 2>&1) && [[ "$response" != *"error"* && "$response" != *"Error"* ]]; then
        applied=true
        break
    fi
    sleep 0.2
done
if [[ "$applied" != true ]]; then
    printf 'Wallpaper was not applied: %s\n' "${response:-Hyprpaper unavailable}" >&2
    notify-send -a minimal -u normal -- "Wallpaper unavailable" "Check that Hyprpaper is running." 2>/dev/null || true
    exit 1
fi
printf '%s\n' "$wall" > "$MINIMAL_STATE/current_wallpaper.tmp"
mv -f -- "$MINIMAL_STATE/current_wallpaper.tmp" "$MINIMAL_STATE/current_wallpaper"
ln -sfn -- "$wall" "$MINIMAL_STATE/wallpaper.set"
pkill -RTMIN+19 -u "${UID:-$(id -u)}" -x waybar 2>/dev/null || true
notify-send -a minimal -t 1500 -i "preferences-desktop-wallpaper" -- "Wallpaper" "$(basename "$wall")" 2>/dev/null || true
