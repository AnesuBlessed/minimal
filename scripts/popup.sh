#!/usr/bin/env bash
# Own only this installation's popup PID, with serialized start/toggle.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
tag=${1:?Popup name}; shift
[[ $tag =~ ^[a-z-]+$ ]] || exit 2
mkdir -p -- "$MINIMAL_RUNTIME"
exec 9>"$MINIMAL_RUNTIME/$tag.lock"
flock 9
pidfile="$MINIMAL_RUNTIME/$tag.pid"
if [[ -r $pidfile ]]; then
    read -r pid start < "$pidfile" || true
    if [[ ${pid:-} =~ ^[0-9]+$ && -r /proc/$pid/stat ]]; then
        current=$(awk '{sub(/^.*\)[[:space:]]+/, ""); print $20}' "/proc/$pid/stat")
        if [[ $current == "${start:-}" ]]; then
            kill "$pid" 2>/dev/null || true
            rm -f -- "$pidfile"
            exit 0
        fi
    fi
fi
# Close any other active bottom popup so overlays never stack or fight for focus grab.
for other_file in "$MINIMAL_RUNTIME"/*.pid; do
    [[ -r $other_file && $other_file != "$pidfile" ]] || continue
    read -r o_pid o_start < "$other_file" || true
    if [[ ${o_pid:-} =~ ^[0-9]+$ && -r /proc/$o_pid/stat ]]; then
        o_cur=$(awk '{sub(/^.*\)[[:space:]]+/, ""); print $20}' "/proc/$o_pid/stat")
        if [[ $o_cur == "${o_start:-}" ]]; then
            kill "$o_pid" 2>/dev/null || true
            rm -f -- "$other_file"
        fi
    fi
done
"$@" 9>&- &
pid=$!
if [[ -r /proc/$pid/stat ]]; then
    printf '%s %s\n' "$pid" "$(awk '{sub(/^.*\)[[:space:]]+/, ""); print $20}' "/proc/$pid/stat")" > "$pidfile"
fi
flock -u 9
wait "$pid" || true
# A replacement may already own the file.
flock 9
[[ ! -r $pidfile || $(cut -d ' ' -f1 "$pidfile") != "$pid" ]] || rm -f -- "$pidfile"
