#!/usr/bin/env bash
set -euo pipefail
root=$(dirname "$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")")
exec "$root/scripts/wallpaper.sh" "${1:?Wallpaper path required}"
