function fish_greeting
    set -l config_root "$HOME/.config"
    if set -q XDG_CONFIG_HOME
        set config_root "$XDG_CONFIG_HOME"
    end
    set -l rice "$config_root/minimal"
    if set -q MINIMAL_ROOT
        set rice "$MINIMAL_ROOT"
    end
    if test -x "$rice/scripts/terminal-greeting.sh"
        "$rice/scripts/terminal-greeting.sh"
    else
        fastfetch
    end
end
