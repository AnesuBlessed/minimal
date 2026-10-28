#!/usr/bin/env bash
set -euo pipefail
if ! command -v checkupdates >/dev/null; then
    printf '%s\n' '{"text":"","tooltip":"Install pacman-contrib to check updates"}'
    exit 0
fi
code=0
updates=$(checkupdates 2>/dev/null) || code=$?
case "$code" in
    0)
        if [[ -z "${updates//[[:space:]]/}" ]]; then
            printf '%s\n' '{"text":"","tooltip":"System is up to date"}'
        else
            count=$(grep -c '[^[:space:]]' <<< "$updates")
            printf '{"text":"󰏖 %d","tooltip":"%d updates available"}\n' "$count" "$count"
        fi
        ;;
    2) printf '%s\n' '{"text":"","tooltip":"System is up to date"}' ;;
    *) printf '%s\n' '{"text":"?","tooltip":"Update check unavailable","class":"unavailable"}' ;;
esac
