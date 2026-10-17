#!/usr/bin/env bash
# Distinguish a successful empty check (exit 2) from missing tools/network errors.
set -uo pipefail
if ! command -v checkupdates >/dev/null 2>&1; then
    printf '{"text":"󰚰 ?","tooltip":"Update check unavailable: install pacman-contrib"}\n'
    exit 0
fi
result=$(checkupdates 2>/dev/null)
status=$?
if ((status == 0)); then
    count=$(printf '%s\n' "$result" | sed '/^$/d' | wc -l)
    printf '{"text":"󰚰 %s","tooltip":"%s updates available"}\n' "$count" "$count"
elif ((status == 2)); then
    printf '{"text":"󰚰 0","tooltip":"System up to date"}\n'
else
    printf '{"text":"󰚰 ?","tooltip":"Update check failed; try again later"}\n'
fi
