#!/usr/bin/env bash
# Hyprpaper 0.8 IPC is shared by the picker and the random shortcut.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
wall=$(realpath -e -- "${1:?Wallpaper path required}")
[[ -f $wall && $wall != *','* && $wall != *$'\n'* ]] || { printf 'Invalid wallpaper path\n' >&2; exit 1; }
mkdir -p -- "$MINIMAL_STATE" "$MINIMAL_CACHE"
# A video apply holds this same descriptor across preview, launch and state save.
lock_path=$(readlink -m -- "$MINIMAL_STATE/wallpaper.lock")
if [[ $(readlink "/proc/$$/fd/9" 2>/dev/null || true) != "$lock_path" ]]; then
    exec 9>"$lock_path"
fi
flock 9
# Keep theme, lock assets and persistence recoverable if any later step fails.
transaction=$(mktemp -d "$MINIMAL_CACHE/wallpaper-transaction-XXXXXXXX")
files=("$MINIMAL_ROOT/theme.json" "$MINIMAL_ROOT/waybar/theme.css"
       "$MINIMAL_ROOT/waybar/design.css" "$MINIMAL_ROOT/wlogout/design.css"
       "$MINIMAL_ROOT/foot/foot.ini" "$MINIMAL_ROOT/fuzzel/fuzzel.ini" "$MINIMAL_ROOT/colors.css"
       "$MINIMAL_ROOT/hypr/colors.lua" "$MINIMAL_ROOT/mako/config"
       "$MINIMAL_ROOT/hypr/hyprlock.conf" "$MINIMAL_ROOT/assets/gtk-accent.css" "$MINIMAL_CACHE/lock.png"
       "$MINIMAL_CACHE/lock-source" "$MINIMAL_STATE/current_wallpaper"
       "$MINIMAL_STATE/wallpapers.json")
for index in "${!files[@]}"; do
    [[ ! -f ${files[index]} ]] || cp -p -- "${files[index]}" "$transaction/$index"
done
committed=false
changed=()
rollback_wallpaper() {
    result=$?
    trap - EXIT
    if ! $committed; then
        for index in "${!files[@]}"; do
            if [[ -f $transaction/$index ]]; then
                cp -p -- "$transaction/$index" "${files[index]}" || true
            else
                rm -f -- "${files[index]}"
            fi
        done
        for monitor in "${changed[@]}"; do
            previous=''
            if [[ -r $MINIMAL_STATE/wallpapers.json ]]; then
                previous=$(jq -r --arg output "${monitor:-all}" '.[$output].preview // .all.preview // empty' "$MINIMAL_STATE/wallpapers.json") || true
            fi
            if [[ -z $previous && -r $MINIMAL_STATE/current_wallpaper ]]; then
                read -r previous < "$MINIMAL_STATE/current_wallpaper" || true
            fi
            if [[ -f $previous ]]; then
                hyprctl hyprpaper wallpaper "$monitor,$previous,cover" >/dev/null 2>&1 || printf 'Wallpaper rollback failed on %s\n' "${monitor:-all}" >&2
            else
                printf 'No previous wallpaper available for rollback on %s\n' "${monitor:-all}" >&2
            fi
        done
    fi
    rm -rf -- "$transaction"
    exit "$result"
}
trap rollback_wallpaper EXIT
# Prepare optional assets before changing the backend. A failure is visible.
"$MINIMAL_ROOT/scripts/prepare-lock.sh" "$wall"
"$MINIMAL_ROOT/scripts/update_fuzzel_colors.py" "$wall"
# Do not save a selection or claim success when the backend rejects it.
outputs=${2:-all}
if [[ $outputs == all ]]; then
    monitors=("")
else
    [[ -n $outputs && $outputs != *$'\n'* ]] || exit 2
    IFS=',' read -r -a monitors <<< "$outputs"
fi
# Stop only video units created by Minimal, never unrelated mpvpaper instances.
if [[ $outputs == all ]]; then
    systemctl --user stop "$MINIMAL_SERVICE_PREFIX-video-*.service" 2>/dev/null || true
else
    systemctl --user stop "$MINIMAL_SERVICE_PREFIX-video-$(printf all | sha256sum | cut -c1-12).service" 2>/dev/null || true
    for output in "${monitors[@]}"; do
        systemctl --user stop "$MINIMAL_SERVICE_PREFIX-video-$(printf '%s' "$output" | sha256sum | cut -c1-12).service" 2>/dev/null || true
    done
fi
for monitor in "${monitors[@]}"; do
    changed+=("$monitor")
    reply=$(hyprctl hyprpaper wallpaper "$monitor,$wall,cover")
    sanitized_reply=${reply//"$wall"/}
    if [[ $sanitized_reply == *[Ee]rror* || $sanitized_reply == *[Ff]ail* ]]; then printf '%s\n' "$reply" >&2; exit 1; fi
done
tmp=$(mktemp "$MINIMAL_STATE/wallpaper-XXXXXXXX")
printf '%s\n' "$wall" > "$tmp"
mv -f -- "$tmp" "$MINIMAL_STATE/current_wallpaper"
"$MINIMAL_ROOT/scripts/wallpaper-state.py" "$wall" "$outputs" image "$wall"
committed=true
if systemctl --user is-active --quiet "$MINIMAL_SERVICE_PREFIX-mako.service"; then
    makoctl reload || printf 'Wallpaper applied, but notification theme reload failed\n' >&2
fi
hyprctl reload >/dev/null || printf 'Wallpaper applied, but compositor theme reload failed\n' >&2
notify-send -a minimal -t 2000 -h string:x-canonical-private-synchronous:wallpaper 'Wallpaper applied' "$(basename "$wall")" || true
