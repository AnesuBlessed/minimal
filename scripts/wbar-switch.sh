#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — WAYBAR LAYOUT SWITCHER
# =============================================================================
#  Cycles through all 17 modular Waybar layouts or selects via Rofi.
#  Usage:
#    wbar-switch.sh next
#    wbar-switch.sh prev
#    wbar-switch.sh select
#    wbar-switch.sh <01-17>
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
mkdir -p -- "$MINIMAL_STATE"

layouts_dir="$MINIMAL_ROOT/waybar/layouts"
state_file="$MINIMAL_STATE/current_waybar_layout"

# Read available layouts (sorted)
shopt -s nullglob
layout_files=("$layouts_dir"/[0-9][0-9].jsonc)
shopt -u nullglob

if ((${#layout_files[@]} == 0)); then
    echo "No layouts found in $layouts_dir" >&2
    exit 1
fi

layouts=()
for lf in "${layout_files[@]}"; do
    base=$(basename "$lf" .jsonc)
    layouts+=("$base")
done

# Current layout
current="01"
if [[ -f "$state_file" ]]; then
    current=$(cat "$state_file")
fi

# Find current index
idx=0
for i in "${!layouts[@]}"; do
    if [[ "${layouts[$i]}" == "$current" ]]; then
        idx=$i
        break
    fi
done

target=""
case "${1:-next}" in
    next)
        next_idx=$(( (idx + 1) % ${#layouts[@]} ))
        target="${layouts[$next_idx]}"
        ;;
    prev)
        next_idx=$(( (idx - 1 + ${#layouts[@]}) % ${#layouts[@]} ))
        target="${layouts[$next_idx]}"
        ;;
    select)
        selected=$(printf '%s\n' "${layouts[@]}" | rofi -dmenu -theme "$MINIMAL_ROOT/rofi/selector.rasi" -p " Layout: ") || exit 0
        [[ -n "$selected" ]] || exit 0
        target="$selected"
        ;;
    *)
        # Direct layout name
        if [[ -f "$layouts_dir/$1.jsonc" ]]; then
            target="$1"
        else
            echo "Unknown layout: $1" >&2
            exit 1
        fi
        ;;
esac

target_file="$layouts_dir/$target.jsonc"
if [[ ! -f "$target_file" ]]; then
    exit 1
fi

# Copy to active config
cp -f "$target_file" "$MINIMAL_ROOT/waybar/config.jsonc"
printf '%s\n' "$target" > "$state_file"

# Reload Waybar cleanly
pkill -SIGUSR2 waybar 2>/dev/null || (pkill -x waybar || true && waybar --config "$MINIMAL_ROOT/waybar/config.jsonc" --style "$MINIMAL_ROOT/waybar/style.css" &)

notify-send -a minimal -t 1500 -i "preferences-desktop-theme" -- "Waybar Layout" "Active layout: $target" 2>/dev/null || true
