#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

value=$(hyprctl -j getoption animations:enabled | jq -r '.bool // .int // false')
case $value in
    true|1)
        # Turn gamemode ON (kill animations, shadows, blur for ultra performance)
        hyprctl eval "hl.config({ animations = { enabled = false }, decoration = { shadow = { enabled = false }, blur = { enabled = false } } })" >/dev/null 2>&1 || true
        command -v notify-send >/dev/null 2>&1 && notify-send -a minimal -t 2000 "󰊴 Gamemode Enabled" "Animations and blur disabled for maximum performance" || true
        ;;
    *)
        # Turn gamemode OFF (restore animations and user's saved blur state)
        blur_val="false"
        if [[ -f "$MINIMAL_STATE/effects.json" ]]; then
            saved_blur=$(jq -r '.blur // false' "$MINIMAL_STATE/effects.json" 2>/dev/null || echo "false")
            [[ "$saved_blur" == "true" ]] && blur_val="true"
        fi
        hyprctl eval "hl.config({ animations = { enabled = true }, decoration = { shadow = { enabled = false }, blur = { enabled = $blur_val } } })" >/dev/null 2>&1 || true
        command -v notify-send >/dev/null 2>&1 && notify-send -a minimal -t 2000 "󰊴 Gamemode Disabled" "Standard desktop visual effects restored" || true
        ;;
esac
