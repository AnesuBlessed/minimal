#!/usr/bin/env bash
set -euo pipefail
case ${1:-region} in
    region|edit) region=$(slurp) || exit 0; [[ -n $region ]] || exit 0; args=(-g "$region");;
    full) args=();;
    *) exit 2;;
esac
capture=$(mktemp --suffix=.png)
trap 'rm -f -- "$capture"' EXIT
grim "${args[@]}" "$capture"
[[ -s $capture ]] || exit 1
if [[ ${1:-region} == edit ]]; then
    if command -v satty >/dev/null 2>&1; then
        satty --filename "$capture" --fullscreen
    else
        wl-copy --type image/png < "$capture"
        notify-send -a minimal -u low "Screenshot copied" "Install satty for annotation mode." 2>/dev/null || true
    fi
else
    wl-copy --type image/png < "$capture"
fi
