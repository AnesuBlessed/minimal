#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../scripts/paths.sh"
run="${QS_RUN_WALLPAPER_PICKER:-$MINIMAL_RUNTIME/wallpaper-picker}"
mkdir -p -- "$run"
action=${1:-stop}
case $action in
    pause|run|stop) printf '%s\n' "$action" > "$run/ddg_search_control" ;;
    *) exit 2 ;;
esac
[[ -r $run/search.pid ]] || exit 0
read -r pid < "$run/search.pid"
[[ $pid =~ ^[0-9]+$ && -r /proc/$pid/cmdline ]] || exit 0
grep -Fq "$MINIMAL_ROOT/quickshell/wallpaper-picker/ddg_search.sh" "/proc/$pid/cmdline" || exit 0
if [[ $action == stop ]]; then
    kill -TERM -- "-$pid" 2>/dev/null || true
    kill -CONT -- "-$pid" 2>/dev/null || true
fi
