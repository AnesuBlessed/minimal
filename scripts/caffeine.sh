#!/usr/bin/env bash
# Inhibit idle actions without removing the lock/suspend event handler.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
unit="$MINIMAL_SERVICE_PREFIX-caffeine.service"
case ${1:-status} in
    toggle)
        if systemctl --user is-active --quiet "$unit"; then
            systemctl --user stop "$unit"
        else
            systemd-run --user --quiet --collect --unit="$unit" --property=PartOf=graphical-session.target \
                systemd-inhibit --what=idle --who=Minimal --why='Caffeine enabled' --mode=block sleep infinity
        fi
        ;;
    status) ;;
    *) printf 'Usage: %s [status|toggle]\n' "${0##*/}" >&2; exit 2 ;;
esac
if systemctl --user is-active --quiet "$unit"; then
    printf '{"text":"󰅶","class":"activated","tooltip":"Caffeine on; suspend locking remains active"}\n'
else
    printf '{"text":"󰛊","class":"deactivated","tooltip":"Caffeine off"}\n'
fi
