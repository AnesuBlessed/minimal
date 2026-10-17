#!/usr/bin/env bash
# One-shot sysfs read; also works on desktops without a battery.
set -euo pipefail
supply_root=${MINIMAL_POWER_SUPPLY_ROOT:-/sys/class/power_supply}
total=0 count=0 charging=false
for supply in "$supply_root"/*; do
    [[ -r $supply/type && -r $supply/capacity ]] || continue
    read -r type < "$supply/type"
    [[ $type == Battery ]] || continue
    read -r capacity < "$supply/capacity"
    [[ $capacity =~ ^[0-9]+$ ]] || continue
    if [[ -r $supply/scope ]] && [[ $(<"$supply/scope") == Device ]]; then continue; fi
    total=$((total + capacity)); count=$((count + 1))
    if [[ -r $supply/status ]]; then
        read -r status < "$supply/status"
        [[ $status != Charging && $status != Full && $status != "Not charging" ]] || charging=true
    fi
done
if ((count == 0)); then printf 'Connected\n';
elif $charging; then printf '󱐋 %s%% · Plugged in\n' "$((total / count))";
else printf '󰁹 %s%%\n' "$((total / count))"; fi
