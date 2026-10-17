#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — SESSION ENTRY POINT
# =============================================================================
# Rice-Agnostic Compositor Isolation & Wayland Session Entry Script
# - Unsets foreign compositor / rice environment variables
# - Cleans up rogue / competing bar and notification daemons
# - Sets pristine Wayland session environment variables
# - Launches Hyprland with Minimal's native Lua configuration
# =============================================================================
set -euo pipefail

if [[ ${1:-} == --config-dir ]]; then
    [[ $# -ge 2 && -n $2 ]] || { printf 'Missing configuration directory\n' >&2; exit 2; }
    export XDG_CONFIG_HOME="$2"
    shift 2
fi

# Rice-Agnostic Compositor Isolation:
# Unset foreign compositor variables that other rices might have exported into login shells
unset HYPRLAND_CONFIG SWAYSOCK

# Ensure clean Wayland environment
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export MINIMAL_ROOT="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

# Detect hardware before the compositor consumes cached GPU flags.
"$MINIMAL_ROOT/scripts/hardware-detect.sh" >/dev/null 2>&1 || true

# Launches Hyprland with Minimal's Lua config
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
exec Hyprland -c "$CONFIG_DIR/hypr/hyprland.lua" "$@"
