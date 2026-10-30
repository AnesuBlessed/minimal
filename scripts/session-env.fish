# Source from fish/conf.d/00-minimal-session.fish before older rice defaults.
set -l minimal_config "$HOME/.config"
if set -q XDG_CONFIG_HOME; and test -n "$XDG_CONFIG_HOME"
    set minimal_config "$XDG_CONFIG_HOME"
end
set -gx HYPRLAND_CONFIG "$minimal_config/hypr/hyprland.lua"
