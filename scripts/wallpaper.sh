#!/usr/bin/env bash
# Hyprpaper 0.8 IPC is shared by the picker and the random shortcut.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
wall=$(realpath -e -- "${1:?Wallpaper path required}")
[[ -f $wall && $wall != *','* && $wall != *$'\n'* ]] || { printf 'Invalid wallpaper path\n' >&2; exit 1; }
mkdir -p -- "$MINIMAL_STATE"
exec 9>"$MINIMAL_STATE/wallpaper.lock"
flock 9
# Do not save a selection or claim success when the backend rejects it.
reply=$(hyprctl hyprpaper wallpaper ",$wall,cover")
if [[ $reply == *[Ee]rror* || $reply == *[Ff]ail* ]]; then printf '%s\n' "$reply" >&2; exit 1; fi
tmp=$(mktemp "$MINIMAL_STATE/wallpaper-XXXXXXXX")
printf '%s\n' "$wall" > "$tmp"
mv -f -- "$tmp" "$MINIMAL_STATE/current_wallpaper"
"$MINIMAL_ROOT/scripts/prepare-lock.sh" "$wall"
"$MINIMAL_ROOT/scripts/update_fuzzel_colors.py" "$wall"
# Reload only the bar started by this installation, not unrelated Waybars.
if [[ -r $MINIMAL_RUNTIME/waybar.pid ]]; then
    read -r bar_pid < "$MINIMAL_RUNTIME/waybar.pid"
    if [[ $bar_pid =~ ^[0-9]+$ && -r /proc/$bar_pid/cmdline ]] && grep -Fq "$MINIMAL_ROOT/waybar/config.jsonc" "/proc/$bar_pid/cmdline"; then kill -USR2 "$bar_pid" 2>/dev/null || true; fi
fi
notify-send -a minimal -t 2000 -h string:x-canonical-private-synchronous:wallpaper 'Wallpaper applied' "$(basename "$wall")"
