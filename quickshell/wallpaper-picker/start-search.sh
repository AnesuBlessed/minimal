#!/usr/bin/env bash
# Search text is an argument, never shell source.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/paths.sh"
cache="${QS_CACHE_WALLPAPER_PICKER:-$MINIMAL_CACHE/wallpaper-picker}"
run="${QS_RUN_WALLPAPER_PICKER:-$MINIMAL_RUNTIME/wallpaper-picker}"
mkdir -p -- "$cache/search_thumbs" "$run/logs"
exec 9>"$run/search-start.lock"
flock 9
if [[ -r $run/search.pid ]]; then
    read -r pid < "$run/search.pid"
    if [[ $pid =~ ^[0-9]+$ && -r /proc/$pid/cmdline ]] && grep -Fq "$MINIMAL_ROOT/quickshell/wallpaper-picker/ddg_search.sh" "/proc/$pid/cmdline"; then
        kill -- "-$pid" 2>/dev/null || true
        kill -CONT -- "-$pid" 2>/dev/null || true
    fi
fi
find "$cache/search_thumbs" -mindepth 1 -maxdepth 1 -type f -delete
rm -f -- "$cache/search_map.txt"
printf 'run\n' > "$run/ddg_search_control"
setsid bash "$MINIMAL_ROOT/quickshell/wallpaper-picker/ddg_search.sh" "${1:?Search query required}" 9>&- >"$run/logs/ddg_run.log" 2>&1 &
printf '%s\n' "$!" > "$run/search.pid"
