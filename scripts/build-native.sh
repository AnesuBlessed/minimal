#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
mkdir -p -- "$MINIMAL_CACHE/bin"
exec 9>"$MINIMAL_CACHE/native-build.lock"
flock 9
output="$MINIMAL_CACHE/bin/automount"
if [[ ! -x $output || $MINIMAL_ROOT/scripts/automount.c -nt $output ]]; then
    temporary=$(mktemp "$MINIMAL_CACHE/bin/automount-XXXXXXXX")
    trap 'rm -f -- "$temporary"' EXIT
    pkg_flags=$(pkg-config --cflags --libs gio-2.0 gio-unix-2.0)
    read -r -a flags <<< "$pkg_flags"
    cc -O2 -Wall -Wextra -Werror "$MINIMAL_ROOT/scripts/automount.c" -o "$temporary" "${flags[@]}"
    chmod 755 "$temporary"
    mv -f -- "$temporary" "$output"
    trap - EXIT
fi

output="$MINIMAL_CACHE/bin/session-guard"
if [[ ! -x $output || $MINIMAL_ROOT/scripts/session-guard.c -nt $output ]]; then
    temporary=$(mktemp "$MINIMAL_CACHE/bin/session-guard-XXXXXXXX")
    trap 'rm -f -- "$temporary"' EXIT
    cc -O2 -Wall -Wextra -Werror "$MINIMAL_ROOT/scripts/session-guard.c" -o "$temporary"
    chmod 755 "$temporary"
    mv -f -- "$temporary" "$output"
    trap - EXIT
fi
