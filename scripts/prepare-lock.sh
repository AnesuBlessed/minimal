#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
wall=${1:?Wallpaper path required}
[[ -f $wall ]] || exit 1
mkdir -p -- "$MINIMAL_CACHE"
avatar="$MINIMAL_ROOT/wallpapers/default-avatar.png"
for candidate in "/var/lib/AccountsService/icons/${USER:-$(id -un)}" "$HOME/.face" "$HOME/.face.icon"; do
    [[ ! -f $candidate ]] || avatar="$candidate"
done
ln -sf -- "$avatar" "$MINIMAL_CACHE/avatar"
exec 9>"$MINIMAL_CACHE/lock-image.lock"
flock 9
fingerprint=$(stat -Lc '%n:%s:%Y' -- "$wall")
if [[ -f $MINIMAL_CACHE/lock.png && -f $MINIMAL_CACHE/lock-source && $(<"$MINIMAL_CACHE/lock-source") == "$fingerprint" ]]; then exit 0; fi
image_tmp=$(mktemp "$MINIMAL_CACHE/lock-XXXXXXXX.png")
trap 'rm -f -- "$image_tmp"' EXIT
# Bound image size before the CPU blur matching the display. No extra daemon or GPU blur at lock time.
target_res=$(hyprctl -j monitors 2>/dev/null | jq -r 'max_by(.width * .height) | "\(.width)x\(.height)"' 2>/dev/null || true)
[[ -n "$target_res" && "$target_res" =~ ^[0-9]+x[0-9]+$ ]] || target_res="1920x1080"
magick "$wall" -auto-orient -resize "${target_res}>" -blur 0x12 -brightness-contrast -25x-5 "$image_tmp"
mv -f -- "$image_tmp" "$MINIMAL_CACHE/lock.png"
printf '%s\n' "$fingerprint" > "$MINIMAL_CACHE/lock-source"
