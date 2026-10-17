#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
[[ -r $MINIMAL_STATE/wallpapers.json ]] || exit 0
# Snapshot first: individual apply operations update the live state file.
state=$(cat "$MINIMAL_STATE/wallpapers.json")
sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.hyprpaper.sock"
for attempt in {1..20}; do
    [[ -S $sock ]] && break
    out=$(hyprctl hyprpaper listloaded 2>&1) && break
    [[ $out == *"invalid hyprpaper request"* ]] && break
    sleep 0.25
done
while IFS= read -r record; do
    output=$(jq -r .key <<< "$record")
    wall=$(jq -r .value.path <<< "$record")
    [[ -f $wall ]] || continue
    if [[ $(jq -r .value.kind <<< "$record") == video ]]; then
        preview=$(jq -r .value.preview <<< "$record")
        "$MINIMAL_ROOT/scripts/wallpaper-video.sh" "$wall" "$output" "$preview" || true
    elif [[ $output == all && -n ${MINIMAL_WALLPAPER:-} && $wall == "$MINIMAL_WALLPAPER" ]]; then
        continue
    else
        "$MINIMAL_ROOT/scripts/wallpaper.sh" "$wall" "$output" || true
    fi
done < <(jq -c 'to_entries | group_by([.value.kind, .value.path, .value.preview, (.key == "all")]) | map({key: (map(.key) | join(",")), value: .[0].value}) | sort_by(.key != "all")[]' <<< "$state")
