#!/usr/bin/env bash
# All paths and downloaded URLs remain arguments, never interpolated shell code.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/paths.sh"
name=${1:?Image name required}
outputs=${2:?Outputs required}
[[ $name =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$ ]] || { printf 'Invalid search image name\n' >&2; exit 2; }
cache="${QS_CACHE_WALLPAPER_PICKER:-$MINIMAL_CACHE/wallpaper-picker}"
source_dir="${MINIMAL_WALLPAPERS:-$MINIMAL_ROOT/wallpapers}"
destination="$source_dir/$name"
mkdir -p -- "$source_dir" "$cache/thumbs" "$cache/colors_markers"
if [[ ! -f $destination ]]; then
    url=$(awk -F'|' -v name="$name" '$1 == name {print $2; exit}' "$cache/search_map.txt")
    [[ $url == https://* || $url == http://* ]] || { printf 'Search URL missing or unsupported\n' >&2; exit 1; }
    temporary=$(mktemp "$source_dir/.download-XXXXXXXX")
    trap 'rm -f -- "$temporary"' EXIT
    curl --silent --show-error --fail --location --max-time 30 --max-filesize 26214400 \
        --proto '=http,https' --proto-redir '=http,https' \
        --user-agent 'Mozilla/5.0' --output "$temporary" -- "$url"
    "$MINIMAL_ROOT/scripts/image-preview.py" "$temporary"
    mv -- "$temporary" "$destination"
fi
"$MINIMAL_ROOT/scripts/image-preview.py" "$destination" "$cache/thumbs/$name"
if command -v magick >/dev/null 2>&1; then
    hex=$(magick "$cache/thumbs/$name" -modulate 100,200 -resize "1x1^" -gravity center -extent 1x1 -depth 8 -format "%[hex:p{0,0}]" info:- 2>/dev/null | grep -oE '[0-9A-Fa-f]{6}' | head -n 1 || true)
    [[ -z $hex ]] || touch "$cache/colors_markers/${name}_HEX_${hex}"
fi
exec "$MINIMAL_ROOT/scripts/wallpaper.sh" "$destination" "$outputs"
