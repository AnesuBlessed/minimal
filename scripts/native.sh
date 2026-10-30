#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
if [[ ! -x "$MINIMAL_ROOT/build/minimal" ]]; then
    printf 'Native helpers are missing. Run %s/scripts/build.sh first.\n' "$MINIMAL_ROOT" >&2
    exit 1
fi
exec "$MINIMAL_ROOT/build/minimal" "$@"
