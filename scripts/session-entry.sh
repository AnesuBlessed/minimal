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

# Rice-Agnostic Compositor Isolation:
# Unset foreign compositor variables that other rices might have exported into login shells
unset HYPRLAND_CONFIG SWAYSOCK

# Ensure clean Wayland environment
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export MINIMAL_ROOT="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

# Cleans up competing daemons generically by binary signature:
# Kill any rogue/zombie bars (waybar, polybar, ironbar) or rogue notification daemons (dunst, swaync)
CURRENT_USER="${USER:-$(id -un)}"
for daemon in waybar polybar ironbar dunst swaync; do
    pkill -u "$CURRENT_USER" -x "$daemon" 2>/dev/null || true
done

# Launches Hyprland with Minimal's Lua config
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
exec Hyprland -c "$CONFIG_DIR/hypr/hyprland.lua" "$@"
