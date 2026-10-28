#!/usr/bin/env bash
# Minimal's CLI and TUI share one deployment engine.
set -euo pipefail
root=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
exec python3 "$root/scripts/install.py" "$@"
