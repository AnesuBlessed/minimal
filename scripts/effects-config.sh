#!/usr/bin/env bash
# Minimal Visual Effects & Desktop Controls Helper
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
mkdir -p "$MINIMAL_STATE" "$MINIMAL_RUNTIME"
exec 9>"$MINIMAL_STATE/effects.lock"
flock -w 5 9 || exit 1

unit="$MINIMAL_SERVICE_PREFIX-night-light.service"
action="${1:-get}"
key="${2:-}"
value="${3:-}"

if [[ "$action" != "get" && "$action" != "set" ]]; then
    echo "Expected get or set" >&2
    exit 1
fi

if [[ "$action" == "set" ]]; then
    case "$key" in
        blur|animations|night_light)
            val_lower="${value,,}"
            case "$val_lower" in
                true|false|1|0|yes|no) ;;
                *) echo "Expected a boolean value" >&2; exit 1 ;;
            esac
            ;;
        launcher)
            if [[ "$value" != "fuzzel" && "$value" != "quickshell" ]]; then
                echo "Unknown launcher" >&2
                exit 1
            fi
            ;;
        temperature)
            if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
                echo "Temperature must be an integer" >&2
                exit 1
            fi
            if [[ "$value" -lt 2000 || "$value" -gt 6500 ]]; then
                echo "Temperature must be between 2000 and 6500" >&2
                exit 1
            fi
            ;;
        *)
            echo "Unknown setting: $key" >&2
            exit 1
            ;;
    esac
fi

json_file="$MINIMAL_STATE/effects.json"
lua_file="$MINIMAL_STATE/effects.lua"
pref_file="$MINIMAL_STATE/launcher.pref"

is_service_active() {
    systemctl --user is-active --quiet "$unit" 2>/dev/null
}

stop_night_light() {
    if is_service_active; then
        systemctl --user stop "$unit" >/dev/null 2>&1 || true
    fi
}

get_hypr_bool() {
    local opt="$1"
    local res
    res=$(hyprctl -j getoption "$opt" 2>/dev/null || true)
    if [[ -n "$res" ]]; then
        local b
        b=$(jq -r 'if .bool != null then .bool elif .int != null then (.int != 0) else false end' <<< "$res" 2>/dev/null || true)
        if [[ "$b" == "true" ]]; then
            echo "true"
            return
        fi
    fi
    echo "false"
}

# Read state
blur=$(get_hypr_bool "decoration:blur:enabled")
animations=$(get_hypr_bool "animations:enabled")
if is_service_active; then
    night_light=true
else
    night_light=false
fi
temperature=4500
launcher="quickshell"

if [[ -f "$pref_file" ]]; then
    pref_val=$(tr -d '[:space:]' < "$pref_file" 2>/dev/null || true)
    if [[ "$pref_val" == "fuzzel" || "$pref_val" == "quickshell" ]]; then
        launcher="$pref_val"
    fi
fi

if [[ -f "$json_file" ]]; then
    saved_parsed=$(jq -r '[ (.temperature // 4500), (.launcher // "quickshell") ] | @tsv' "$json_file" 2>/dev/null || true)
    if [[ -n "$saved_parsed" ]]; then
        read -r s_temp s_launch <<< "$saved_parsed"
        [[ -n "$s_temp" && "$s_temp" =~ ^[0-9]+$ ]] && temperature="$s_temp"
        [[ "$s_launch" == "fuzzel" || "$s_launch" == "quickshell" ]] && launcher="$s_launch"
    fi
fi

if [[ "$action" == "get" ]]; then
    jq -n \
        --argjson blur "$blur" \
        --argjson animations "$animations" \
        --argjson night_light "$night_light" \
        --argjson temp "$temperature" \
        --arg launcher "$launcher" \
        '{"blur": $blur, "animations": $animations, "night_light": $night_light, "temperature": $temp, "launcher": $launcher}'
    exit 0
fi

if [[ "$action" == "set" ]]; then
    case "$key" in
        blur)
            val_lower="${value,,}"
            [[ "$val_lower" =~ ^(true|1|yes)$ ]] && blur=true || blur=false
            hyprctl eval "hl.config({ decoration = { blur = { enabled = ${blur} } } })" >/dev/null
            ;;
        animations)
            val_lower="${value,,}"
            [[ "$val_lower" =~ ^(true|1|yes)$ ]] && animations=true || animations=false
            hyprctl eval "hl.config({ animations = { enabled = ${animations} } })" >/dev/null
            ;;
        launcher)
            launcher="$value"
            tmp_pref=$(mktemp "$MINIMAL_STATE/.pref-XXXXXXXX")
            printf '%s\n' "$value" > "$tmp_pref"
            mv -f "$tmp_pref" "$pref_file"
            ;;
        night_light)
            val_lower="${value,,}"
            [[ "$val_lower" =~ ^(true|1|yes)$ ]] && night_light=true || night_light=false
            if [[ "$night_light" == "true" ]]; then
                stop_night_light
                systemd-run --user --quiet --collect \
                    --unit="$unit" \
                    --property=PartOf=graphical-session.target \
                    --property=Type=exec \
                    --setenv=WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
                    --setenv=HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-}" \
                    hyprsunset -t "$temperature" >/dev/null
            else
                stop_night_light
            fi
            ;;
        temperature)
            temperature="$value"
            if [[ "$temperature" -lt 2000 ]]; then temperature=2000; fi
            if [[ "$temperature" -gt 6500 ]]; then temperature=6500; fi
            if [[ "$night_light" == "true" ]]; then
                stop_night_light
                systemd-run --user --quiet --collect \
                    --unit="$unit" \
                    --property=PartOf=graphical-session.target \
                    --property=Type=exec \
                    --setenv=WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
                    --setenv=HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-}" \
                    hyprsunset -t "$temperature" >/dev/null
            fi
            ;;
    esac

    if [[ "$key" == "blur" || "$key" == "animations" ]]; then
        lua_content="-- Generated by Minimal effects-config.sh
hl.config({
    decoration = {
        blur = {
            enabled = ${blur},
        },
    },
    animations = {
        enabled = ${animations},
    },
})
"
        tmp_lua=$(mktemp "$MINIMAL_STATE/.effects-lua-XXXXXXXX")
        printf '%s' "$lua_content" > "$tmp_lua"
        mv -f "$tmp_lua" "$lua_file"
    fi

    tmp_json=$(mktemp "$MINIMAL_STATE/.effects-json-XXXXXXXX")
    jq -n \
        --argjson blur "$blur" \
        --argjson animations "$animations" \
        --argjson night_light "$night_light" \
        --argjson temp "$temperature" \
        --arg launcher "$launcher" \
        '{"blur": $blur, "animations": $animations, "night_light": $night_light, "temperature": $temp, "launcher": $launcher}' > "$tmp_json"
    mv -f "$tmp_json" "$json_file"

    cat "$json_file"
fi
