# Source from uwsm/env-hyprland.d/99-minimal-session.sh.
# Explicitly select the linked Minimal config instead of inherited rice defaults.
export HYPRLAND_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
