#!/usr/bin/env bash
# Inhibit idle actions without removing the lock/suspend event handler.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
unit="$MINIMAL_SERVICE_PREFIX-caffeine.service"
mkdir -p "$MINIMAL_RUNTIME"
exec 9>"$MINIMAL_RUNTIME/caffeine.lock"
flock 9
case ${1:-status} in
    toggle)
        if systemctl --user is-active --quiet "$unit"; then
            systemctl --user stop "$unit"
            rm -f "${MINIMAL_RUNTIME:-/run/user/${UID:-$(id -u)}/minimal}/caffeine.inhibit" 2>/dev/null || true
        else
            mkdir -p "${MINIMAL_RUNTIME:-/run/user/${UID:-$(id -u)}/minimal}" 2>/dev/null || true
            systemd-run --user --quiet --collect --unit="$unit" --property=PartOf=graphical-session.target \
                systemd-inhibit --what=idle --who=Minimal --why='Caffeine enabled' --mode=block sleep infinity
        fi
        systemctl --user kill --kill-whom=main --signal=RTMIN+9 "$MINIMAL_SERVICE_PREFIX-waybar.service" 2>/dev/null || true
        ;;
    status) ;;
    *) printf 'Usage: %s [status|toggle]\n' "${0##*/}" >&2; exit 2 ;;
esac
if systemctl --user is-active --quiet "$unit"; then
    touch "${MINIMAL_RUNTIME:-/run/user/${UID:-$(id -u)}/minimal}/caffeine.inhibit" 2>/dev/null || true
    printf '{"text":"󰅶","class":"activated","tooltip":"Caffeine on; suspend locking remains active"}\n'
else
    rm -f "${MINIMAL_RUNTIME:-/run/user/${UID:-$(id -u)}/minimal}/caffeine.inhibit" 2>/dev/null || true
    printf '{"text":"󰛊","class":"deactivated","tooltip":"Caffeine off"}\n'
fi
