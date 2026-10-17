#!/usr/bin/env bash
# Operate on this compositor's service, never every bar belonging to the user.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
unit="$MINIMAL_SERVICE_PREFIX-waybar.service"
case ${1:---reload} in
    --start|start)
        exec waybar -c "$MINIMAL_ROOT/waybar/config.jsonc" -s "$MINIMAL_ROOT/waybar/style.css";;
    --reload|reload) signal=USR2;;
    --toggle|toggle) signal=USR1;;
    --restart|restart) exec systemctl --user restart "$unit";;
    *) printf 'Usage: %s --start|--reload|--toggle|--restart\n' "$0" >&2; exit 2;;
esac
if systemctl --user is-active --quiet "$unit"; then
    exec systemctl --user kill --kill-whom=main --signal="$signal" "$unit"
fi
exec systemd-run --user --quiet --collect --unit="$unit" --property=PartOf=graphical-session.target --property=Restart=on-failure \
    --setenv="WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}" \
    --setenv="HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE:-}" \
    --setenv="MINIMAL_ROOT=$MINIMAL_ROOT" --setenv="MINIMAL_CACHE=$MINIMAL_CACHE" \
    --setenv="MINIMAL_STATE=$MINIMAL_STATE" --setenv="MINIMAL_RUNTIME=$MINIMAL_RUNTIME" \
    "$MINIMAL_ROOT/scripts/waybar.sh" --start
