#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — HYPRIDLE TIMEOUT & POWER MANAGEMENT CONFIGURATOR
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

IDLE_STATE="$MINIMAL_STATE/idle.json"
IDLE_CONF="$MINIMAL_STATE/hypridle.conf"

mkdir -p "$MINIMAL_STATE"

get_val() {
    local key="$1"
    local default="$2"
    if [[ -f "$IDLE_STATE" ]]; then
        python3 -c "import json, sys; d=json.load(open('$IDLE_STATE')); print(d.get('$key', $default))" 2>/dev/null || echo "$default"
    else
        echo "$default"
    fi
}

generate_conf() {
    local blank="$1"
    local sleep_sec="$2"

    cat <<EOF > "$IDLE_CONF"
# Generated dynamically by Minimal idle-config.sh
general {
    lock_cmd = "$MINIMAL_ROOT/scripts/lock.sh"
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms("on")'
    inhibit_sleep = 3
}

listener {
    timeout = 300
    on-timeout = loginctl lock-session
}
EOF

    if [[ "$blank" -gt 0 ]]; then
        cat <<EOF >> "$IDLE_CONF"

listener {
    timeout = $blank
    on-timeout = hyprctl dispatch 'hl.dsp.dpms("off")'
    on-resume = hyprctl dispatch 'hl.dsp.dpms("on")'
}
EOF
    fi

    if [[ "$sleep_sec" -gt 0 ]]; then
        cat <<EOF >> "$IDLE_CONF"

listener {
    timeout = $sleep_sec
    on-timeout = systemctl suspend
}
EOF
    fi
}

apply_and_reload() {
    local blank="$1"
    local sleep_sec="$2"
    python3 -c "import json; json.dump({'blank': $blank, 'sleep': $sleep_sec}, open('$IDLE_STATE', 'w'), indent=2)"
    generate_conf "$blank" "$sleep_sec"

    # Reload hypridle if running
    if systemctl --user is-active --quiet "$MINIMAL_SERVICE_PREFIX-hypridle.service" 2>/dev/null; then
        systemctl --user restart "$MINIMAL_SERVICE_PREFIX-hypridle.service" 2>/dev/null || true
    elif pgrep -x hypridle >/dev/null; then
        pkill -x hypridle || true
        hypridle --config "$IDLE_CONF" >/dev/null 2>&1 &
    fi
}

case "${1:-status}" in
    status)
        b=$(get_val "blank" 300)
        s=$(get_val "sleep" 1800)
        printf '{"blank":%s,"sleep":%s}\n' "$b" "$s"
        ;;
    set-blank)
        val="${2:-300}"
        curr_sleep=$(get_val "sleep" 1800)
        apply_and_reload "$val" "$curr_sleep"
        printf '{"blank":%s,"sleep":%s}\n' "$val" "$curr_sleep"
        ;;
    set-sleep)
        val="${2:-1800}"
        curr_blank=$(get_val "blank" 300)
        apply_and_reload "$curr_blank" "$val"
        printf '{"blank":%s,"sleep":%s}\n' "$curr_blank" "$val"
        ;;
    *)
        echo "Usage: idle-config.sh [status|set-blank <seconds>|set-sleep <seconds>]" >&2
        exit 2
        ;;
esac
