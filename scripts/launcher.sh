#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
# Toggle: if fuzzel is already open, kill existing instance and return cleanly
if pgrep -x fuzzel >/dev/null 2>&1; then
    pkill -x fuzzel || true
    exit 0
fi

# Fuzzel ignores margins with anchor=center. A top anchor centers horizontally;
# calculate the vertical margin in logical pixels on the focused monitor.
geometry=$(hyprctl -j monitors 2>/dev/null | jq -r '
    (map(select(.focused)) | first) // empty |
    [(.name), (if (.transform % 2) == 1 then .width else .height end) / .scale] | @tsv' 2>/dev/null) || geometry=''
args=(--config "$MINIMAL_ROOT/fuzzel/fuzzel.ini")
if [[ -n $geometry ]]; then
    IFS=$'\t' read -r output height <<< "$geometry"
    if [[ $height =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        height=${height%.*}
        lines=8
        # Leave room around the panel even on a small or heavily scaled display.
        ((height >= 500)) || lines=5
        panel_height=$(((lines + 1) * 30 + 46))
        margin=$(((height - panel_height) / 2 + 40))
        ((margin >= 12)) || margin=12
        ((margin + panel_height <= height - 12)) || margin=$((height - panel_height - 12))
        ((margin >= 0)) || margin=0
        args+=(--output "$output" --anchor top --y-margin "$margin" --lines "$lines")
    fi
fi
fuzzel "${args[@]}" "$@" || true
exit 0
