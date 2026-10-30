#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
# The README is the shared, human-readable shortcut reference.
awk -F '|' '/^## Keybindings/{in_keys=1} in_keys && /^\| `/{gsub(/`/, ""); gsub(/^[ \t]+|[ \t]+$/, "", $2); gsub(/^[ \t]+|[ \t]+$/, "", $3); print $2 "  —  " $3}' "$MINIMAL_ROOT/README.md" |
    rofi -dmenu -i -theme "$MINIMAL_ROOT/rofi/selector.rasi" -theme-str "$("$MINIMAL_ROOT/scripts/theme.sh" --rofi)" -p 'Keyboard shortcuts' >/dev/null || true
