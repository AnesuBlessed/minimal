#!/usr/bin/env bash
# Short event handlers only: native PipeWire/backlight controls + Mako progress OSD.
set -euo pipefail
export LC_ALL=C
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
kind=${1:-}; action=${2:-}
case "$kind:$action" in
    volume:up|volume:down|volume:mute|mic:up|mic:down|mic:mute|brightness:up|brightness:down) ;;
    *) printf 'Usage: %s volume up|down|mute / mic up|down|mute / brightness up|down\n' "$0" >&2; exit 2 ;;
esac
mkdir -p -- "$MINIMAL_RUNTIME"
exec 9>"$MINIMAL_RUNTIME/media-$kind.lock"
flock -w 2 9 || exit 0
if [[ $kind == brightness ]]; then
    command -v brightnessctl >/dev/null || { printf 'Install brightnessctl for backlight control.\n' >&2; exit 1; }
    step=5%+; [[ $action != down ]] || step=5%-
    # Restrict discovery to screen backlights and keep the display above zero.
    brightnessctl --class=backlight --min-value=1 set "$step" >/dev/null
    current=$(brightnessctl --class=backlight get)
    maximum=$(brightnessctl --class=backlight max)
    [[ $current =~ ^[0-9]+$ && $maximum =~ ^[0-9]+$ && $maximum -gt 0 ]] || exit 1
    percent=$(((current * 100 + maximum / 2) / maximum))
    title="󰃠  Brightness  $percent%"
else
    node=@DEFAULT_AUDIO_SINK@; icon='󰕾'; name=Volume
    if [[ $kind == mic ]]; then node=@DEFAULT_AUDIO_SOURCE@; icon='󰍬'; name=Microphone; fi
    case $action in
        up) wpctl set-volume -l 1.0 "$node" 5%+ ;;
        down) wpctl set-volume "$node" 5%- ;;
        mute) wpctl set-mute "$node" toggle ;;
    esac
    reading=$(wpctl get-volume "$node")
    read -r _ level _ <<< "$reading"
    [[ $level =~ ^[0-9]+([.][0-9]+)?$ ]] || exit 1
    percent=$(awk -v volume="$level" 'BEGIN { printf "%.0f", volume * 100 }')
    if [[ $reading == *MUTED* ]]; then
        title="󰝟  $name muted"; percent=0
    else title="$icon  $name  $percent%"; fi
fi
((percent <= 100)) || percent=100
notify-send -a minimal-osd -u low -t 1200 \
    -h "string:x-canonical-private-synchronous:$kind" \
    -h "int:value:$percent" -h boolean:transient:true "$title"
