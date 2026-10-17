#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — BATTERY PROTECTION & MONITORING DAEMON / CHECKER
# =============================================================================
#  One-shot check scheduled by a native systemd timer:
#  - Low Battery warning at <= 20%
#  - Critical Battery alert at <= 10%
#  - Emergency Suspend protection at <= 5% to prevent data loss / sudden powercut
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

check_battery() {
    local supply_root="${MINIMAL_POWER_SUPPLY_ROOT:-/sys/class/power_supply}"
    local total=0 count=0 charging=true percent=101

    for supply in "$supply_root"/*; do
        [[ -r $supply/type && -r $supply/capacity ]] || continue
        read -r type < "$supply/type"
        [[ $type == Battery ]] || continue
        read -r capacity < "$supply/capacity"
        [[ $capacity =~ ^[0-9]+$ ]] || continue
        # Exclude peripheral batteries (mouse/headset), and protect the lowest
        # discharging system pack rather than averaging away a critical pack.
        if [[ -r $supply/scope ]] && [[ $(<"$supply/scope") == Device ]]; then continue; fi
        local status="Unknown"
        [[ ! -r $supply/status ]] || read -r status < "$supply/status"
        if [[ $status != Charging && $status != Full && $status != "Not charging" ]]; then
            charging=false
            ((capacity >= percent)) || percent=$capacity
        fi
        total=$((total + capacity))
        count=$((count + 1))
    done

    # If no battery found on this system, nothing to monitor
    ((count > 0)) || return 0

    ((percent <= 100)) || percent=$((total / count))
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
        # Recheck after resume; the emergency tier must not suppress protection.
        notify-send -u critical -a minimal-power -t 5000 \
            -h string:x-canonical-private-synchronous:battery \
            "󰂃 Emergency Battery (${percent}%)" "Suspending system now to prevent shutdown..." || true
        sleep 2
        if systemctl suspend; then
            printf 'emergency\n' > "$state_file"
        else
            loginctl lock-session || true
        fi
    elif ((percent <= 10)); then
        if [[ $last_tier != "critical" && $last_tier != "emergency" ]]; then
            printf 'critical\n' > "$state_file"
            notify-send -u critical -a minimal-power -t 0 \
                -h string:x-canonical-private-synchronous:battery \
                "󰂃 Critical Battery (${percent}%)" "Battery level is critical! Connect charger immediately." || true
        fi
    elif ((percent <= 20)); then
        if [[ $last_tier == "normal" ]]; then
            printf 'low\n' > "$state_file"
            notify-send -u normal -a minimal-power -t 8000 \
                -h string:x-canonical-private-synchronous:battery \
                "󰂃 Low Battery (${percent}%)" "Battery is running low. Please plug in your charger." || true
        fi
    else
        if [[ $last_tier != "normal" ]]; then
            printf 'normal\n' > "$state_file"
        fi
    fi
}

# A native systemd timer (or --check in tests/preflight) invokes this one-shot checker.
check_battery
