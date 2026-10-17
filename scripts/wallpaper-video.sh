#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
video=$(realpath -e -- "${1:?Video required}")
outputs=${2:-all}
preview=${3:?Preview required}
[[ ! -e $preview ]] || preview=$(realpath -e -- "$preview")
command -v mpvpaper >/dev/null || { printf 'Video wallpaper requires mpvpaper\n' >&2; exit 1; }
[[ -f $video ]] || exit 1
mkdir -p -- "$MINIMAL_STATE"
exec 9>"$MINIMAL_STATE/wallpaper.lock"
flock 9
"$MINIMAL_ROOT/scripts/wallpaper.sh" "$preview" "$outputs"
started=()
complete=false
cleanup() {
    result=$?
    if ! $complete; then
        # The committed still preview is the fallback; stop any partial video set.
        for unit in "${started[@]}"; do systemctl --user stop "$unit.service" 2>/dev/null || true; done
    fi
    exit "$result"
}
trap cleanup EXIT
IFS=',' read -r -a monitors <<< "$outputs"
for output in "${monitors[@]}"; do
    target=$output
    [[ $target != all ]] || target='*'
    unit="$MINIMAL_SERVICE_PREFIX-video-$(printf '%s' "$output" | sha256sum | cut -c1-12)"
    # Record before systemd-run so cleanup stops partially registered transient units if launch fails.
    started+=("$unit")
    systemd-run --user --quiet --collect --unit="$unit" --property=PartOf=graphical-session.target --property=Type=exec \
        --setenv="WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}" \
        mpvpaper -o 'loop --no-audio --hwdec=auto --profile=fast' "$target" "$video"
done
"$MINIMAL_ROOT/scripts/wallpaper-state.py" "$video" "$outputs" video "$preview"
complete=true
