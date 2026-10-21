#!/usr/bin/env bash
# Share Foot's server; --no-wait reports launch failure, not the shell's exit code.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
user_shell=${SHELL:-/bin/sh}
if (($# == 0)) && [[ ${user_shell##*/} == fish ]]; then
    set -- "$user_shell" --init-command 'source "$MINIMAL_ROOT/fastfetch/greeting.fish"'
fi
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
if [[ -S ${XDG_RUNTIME_DIR:-/nonexistent}/foot-${WAYLAND_DISPLAY:-none}.sock ]]; then
    if footclient --no-wait --client-environment "$@"; then
        exit 0
    fi
fi
exec foot "$@"
