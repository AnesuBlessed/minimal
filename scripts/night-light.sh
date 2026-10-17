#!/usr/bin/env bash
# Toggle only the night-light service owned by this compositor.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
unit="$MINIMAL_SERVICE_PREFIX-night-light.service"
if systemctl --user is-active --quiet "$unit"; then
    exec systemctl --user stop "$unit"
fi
command -v hyprsunset >/dev/null || { notify-send -a minimal 'Night light unavailable' 'Install hyprsunset to enable this feature.' || true; exit 1; }
exec systemd-run --user --quiet --collect --unit="$unit" --property=PartOf=graphical-session.target \
    --setenv="WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}" \
    --setenv="HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE:-}" hyprsunset -t 4500
