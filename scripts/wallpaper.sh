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

# Build deduplicated map of available wallpapers with category prefixes
declare -A wall_map
choices=()

while IFS=$'\t' read -r label path; do
    [[ -n "$label" && -f "$path" ]] || continue
    if [[ -z "${wall_map["$label"]:-}" ]]; then
        wall_map["$label"]="$path"
        choices+=("$label")
    fi
done < <(python3 - <<'PYCODE'
import os, sys
from pathlib import Path
roots = [
    Path(os.environ.get('MINIMAL_ROOT', '.')) / 'wallpapers',
    Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'minimal/wallpapers',
    Path.home() / 'Documents/Wallpapers',
    Path.home() / 'Pictures/Wallpapers',
]
seen = set()
for r in roots:
    if not r.is_dir(): continue
    for p in sorted(r.rglob('*')):
        if p.is_file() and p.suffix.lower() in ('.jpg', '.jpeg', '.png', '.webp'):
            rel = p.relative_to(r)
            cat = rel.parts[0] if len(rel.parts) > 1 else 'General'
            name = rel.name
            key = (cat, name)
            if key not in seen:
                seen.add(key)
                try:
                    print(f"[{cat}]  {name}\t{p.resolve()}")
                except BrokenPipeError:
                    sys.exit(0)
PYCODE
)

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
        else
            for def in "japan_lake.jpg" "cat_minimal.jpg" "minimal_squares.png"; do
                for c in "${choices[@]}"; do
                    if [[ "$c" == *"$def"* ]]; then
                        wall="${wall_map["$c"]}"
                        break 2
                    fi
                done
            done
            if [[ -z "$wall" && ${#choices[@]} -gt 0 ]]; then
                wall="${wall_map["${choices[0]}"]}"
            fi
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
