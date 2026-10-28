#!/usr/bin/env bash
# Select per invocation; never rewrite the shared current.png symlink.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
shopt -s nullglob
pictures=()
for picture in "$MINIMAL_ROOT"/fastfetch/assets/*.png; do
    [[ ${picture##*/} == current.png ]] || pictures+=("$picture")
done
options=(--config "$MINIMAL_ROOT/fastfetch/config.jsonc")
if [[ -f "$MINIMAL_STATE/fastfetch.png" ]]; then
    options+=(--logo "$MINIMAL_STATE/fastfetch.png")
elif ((${#pictures[@]})); then
    options+=(--logo "${pictures[RANDOM % ${#pictures[@]}]}")
fi
exec fastfetch "${options[@]}" "$@"
