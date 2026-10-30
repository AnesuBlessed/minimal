#!/usr/bin/env bash
set -euo pipefail
root=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
exec "$root/scripts/native.sh" install "$@"
