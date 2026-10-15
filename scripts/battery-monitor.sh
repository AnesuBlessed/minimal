#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — BATTERY PROTECTION & MONITORING DAEMON / CHECKER
# =============================================================================
#  Event-driven / low-power monitoring:
#  - Low Battery warning at <= 20%
#  - Critical Battery alert at <= 10%
#  - Emergency Suspend protection at <= 5% to prevent data loss / sudden powercut
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

check_battery() {
    local supply_root="${MINIMAL_POWER_SUPPLY_ROOT:-/sys/class/power_supply}"
    local total=0 count=0 charging=false

    for supply in "$supply_root"/*; do
        [[ -r $supply/type && -r $supply/capacity ]] || continue
        read -r type < "$supply/type"
        [[ $type == Battery ]] || continue
        read -r capacity < "$supply/capacity"
        [[ $capacity =~ ^[0-9]+$ ]] || continue
        total=$((total + capacity))
        count=$((count + 1))
        if [[ -r $supply/status ]]; then
            read -r status < "$supply/status"
            [[ $status != Charging && $status != Full ]] || charging=true
        fi
    done

    # If no battery found on this system, nothing to monitor
    ((count > 0)) || return 0

    local percent=$((total / count))
    mkdir -p -- "$MINIMAL_RUNTIME"
    local state_file="$MINIMAL_RUNTIME/battery_tier"
    local last_tier="normal"
    [[ ! -r $state_file ]] || read -r last_tier < "$state_file"

    if $charging; then
        if [[ $last_tier != "normal" ]]; then
            printf 'normal\n' > "$state_file"
        fi
        return 0
    fi

    # Discharging checks
    if ((percent <= 5)); then
        if [[ $last_tier != "emergency" ]]; then
            printf 'emergency\n' > "$state_file"
            notify-send -u critical -a minimal-power -t 5000 \
                -h string:x-canonical-private-synchronous:battery \
                "󰂃 Emergency Battery (${percent}%)" "Suspending system now to prevent shutdown..."
            sleep 2
            systemctl suspend || loginctl lock-session
        fi
    elif ((percent <= 10)); then
        if [[ $last_tier != "critical" && $last_tier != "emergency" ]]; then
            printf 'critical\n' > "$state_file"
            notify-send -u critical -a minimal-power -t 0 \
                -h string:x-canonical-private-synchronous:battery \
                "󰂃 Critical Battery (${percent}%)" "Battery level is critical! Connect charger immediately."
        fi
    elif ((percent <= 20)); then
        if [[ $last_tier == "normal" ]]; then
            printf 'low\n' > "$state_file"
            notify-send -u normal -a minimal-power -t 8000 \
                -h string:x-canonical-private-synchronous:battery \
                "󰂃 Low Battery (${percent}%)" "Battery is running low. Please plug in your charger."
        fi
    else
        if [[ $last_tier != "normal" ]]; then
            printf 'normal\n' > "$state_file"
        fi
    fi
}

# If passed --check, run once (for testing / preflight)
if [[ "${1:-}" == "--check" ]]; then
    check_battery
    exit 0
fi

# Daemon loop: sleep 60s (zero CPU overhead)
while true; do
    check_battery
    sleep 60
done
