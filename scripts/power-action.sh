#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
action=${1:-}
case $action in
    lock) exec "$MINIMAL_ROOT/scripts/lock.sh" ;;
    logout) exec hyprctl dispatch 'hl.dsp.exit()' ;;
    suspend) capability=CanSuspend ;;
    hibernate) capability=CanHibernate ;;
    reboot) capability=CanReboot ;;
    poweroff) capability=CanPowerOff ;;
    *) exit 2 ;;
esac
available=$(busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager "$capability") || available=''
case $available in
    's "yes"'|'s "challenge"') ;;
    *) notify-send -a minimal 'Power action unavailable' "$action is not supported or permitted by this system."; exit 1 ;;
esac
exec systemctl "$action"
