#!/usr/bin/env bash
# Complete clipboard mutations before updating the UI or replacing clipboard data.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
cache="${QS_CACHE_CLIPBOARD:-$MINIMAL_CACHE/clipboard}"
mkdir -p -m 700 -- "$cache"
chmod 700 "$cache"
exec 9>"$cache/.action.lock"
flock 9
case "${1:-}" in
    copy)
        [[ ${2:-} =~ ^[0-9]+$ ]] || exit 2
        tmp=$(mktemp "$cache/.copy-XXXXXXXX")
        trap 'rm -f -- "$tmp"' EXIT
        cliphist decode "$2" > "$tmp"
        wl-copy 9>&- < "$tmp"
        ;;
    delete)
        [[ ${2:-} =~ ^[0-9]+$ ]] || exit 2
        rm -f -- "$cache/.search.json" "$cache/.search.json.tmp"
        printf '%s\n' "$2" | cliphist delete
        rm -f -- "$cache/$2.png" "$cache/$2.png.tmp"
        ;;
    wipe)
        rm -f -- "$cache/.search.json" "$cache/.search.json.tmp"
        cliphist wipe
        find "$cache" -maxdepth 1 -type f \( -name '*.png' -o -name '*.png.tmp' \) -delete
        ;;
    *) printf 'Usage: %s copy ID | delete ID | wipe\n' "$0" >&2; exit 2 ;;
esac
