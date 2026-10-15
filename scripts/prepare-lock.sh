#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
wall=${1:?Wallpaper path required}
[[ -f $wall ]] || exit 1
mkdir -p -- "$MINIMAL_CACHE"
exec 9>"$MINIMAL_CACHE/lock-image.lock"
flock 9
fingerprint=$(stat -Lc '%n:%s:%Y' -- "$wall")
if [[ -f $MINIMAL_CACHE/lock.png && -f $MINIMAL_CACHE/lock-source && $(<"$MINIMAL_CACHE/lock-source") == "$fingerprint" ]]; then exit 0; fi
image_tmp=$(mktemp "$MINIMAL_CACHE/lock-XXXXXXXX.png")
trap 'rm -f -- "$image_tmp"' EXIT
# Bound image size before the CPU blur. No extra daemon or GPU blur at lock time.
magick "$wall" -auto-orient -resize '1920x1080>' -blur 0x12 -brightness-contrast -25x-5 "$image_tmp"
mv -f -- "$image_tmp" "$MINIMAL_CACHE/lock.png"
printf '%s\n' "$fingerprint" > "$MINIMAL_CACHE/lock-source"
