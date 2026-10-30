#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — WI-FI & NETWORK MANAGER (ROFI INTERFACE)
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

action="${1:-menu}"

# 1. Clean Wi-Fi Radio Toggle (Uses NetworkManager, avoids rfkill/iwd desync)
if [[ "$action" == "toggle" ]]; then
    status=$(nmcli radio wifi 2>/dev/null || echo "disabled")
    if [[ "$status" == "enabled" ]]; then
        nmcli radio wifi off
        notify-send -u low -i network-wireless-offline-symbolic "Wi-Fi" "Wi-Fi disabled"
    else
        nmcli radio wifi on
        notify-send -u low -i network-wireless-signal-good-symbolic "Wi-Fi" "Wi-Fi enabled"
    fi
    exit 0
fi

# 2. If Wi-Fi is disabled, prompt to enable
wifi_status=$(nmcli radio wifi 2>/dev/null || echo "disabled")
if [[ "$wifi_status" != "enabled" ]]; then
    choice=$(printf "󰖩  Enable Wi-Fi\n󰒓  Network Settings\n" | rofi -dmenu \
        -theme "$MINIMAL_ROOT/rofi/selector.rasi" \
        -theme-str "$("$MINIMAL_ROOT/scripts/rofi-images.sh" selector 2>/dev/null || "$MINIMAL_ROOT/scripts/theme.sh" --rofi 2>/dev/null || true)" \
        -p "󰤮 Wi-Fi: " 2>/dev/null || true)
    case "${choice:-}" in
        *"Enable Wi-Fi"*)
            nmcli radio wifi on
            notify-send -u low -i network-wireless-signal-good-symbolic "Wi-Fi" "Wi-Fi enabled"
            ;;
        *"Network Settings"*)
            nm-connection-editor &
            ;;
    esac
    exit 0
fi

# Toggle: close if selector rofi is already open
uid="${UID:-$(id -u)}"
if pgrep -u "$uid" -f "rofi.*selector\.rasi" >/dev/null 2>&1; then
    pkill -u "$uid" -f "rofi.*selector\.rasi" || true
    exit 0
fi
pkill -u "$uid" -x rofi 2>/dev/null || true

# Scan networks and prepare menu entries
active_ssid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}' || true)

# Collect unique SSIDs with signal and security
mapfile -t wifi_lines < <(nmcli -t -f "IN-USE,SSID,SIGNAL,SECURITY,BARS" device wifi list --rescan yes 2>/dev/null | awk -F: '
    $2 != "" && !seen[$2]++ {
        in_use = ($1 == "*") ? "󰄬 " : "  "
        sec = ($4 != "" && $4 !~ /--/) ? "🔒" : "  "
        printf "%s%-25s %3s%% %s %s\n", in_use, $2, $3, $5, sec
    }
' || true)

menu_items="󰑐  Rescan Networks\n󰒓  Network Settings"
if [[ -n "$active_ssid" ]]; then
    menu_items="󰖪  Disconnect ($active_ssid)\n$menu_items"
fi

for line in "${wifi_lines[@]}"; do
    [[ -n "$line" ]] || continue
    menu_items+="\n$line"
done

chosen=$(printf '%b' "$menu_items" | rofi -dmenu \
    -theme "$MINIMAL_ROOT/rofi/selector.rasi" \
    -theme-str "$("$MINIMAL_ROOT/scripts/rofi-images.sh" selector 2>/dev/null || "$MINIMAL_ROOT/scripts/theme.sh" --rofi 2>/dev/null || true)" \
    -p "󰖩 Wi-Fi: " 2>/dev/null || true)

[[ -n "${chosen:-}" ]] || exit 0

case "$chosen" in
    *"Rescan Networks"*)
        exec "$0" menu
        ;;
    *"Network Settings"*)
        nm-connection-editor &
        ;;
    *"Disconnect"*)
        if [[ -n "$active_ssid" ]]; then
            nmcli connection down id "$active_ssid" || true
            notify-send -u normal -i network-wireless-offline-symbolic "Wi-Fi" "Disconnected from $active_ssid"
        fi
        ;;
    *)
        # Extract SSID: skip first 2 characters (active mark) and extract SSID until signal percentage
        target_ssid=$(echo "$chosen" | sed 's/^..//' | sed -E 's/[[:space:]]+[0-9]+%.*//' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [[ -n "$target_ssid" ]] || exit 0

        # If already active, notify
        if [[ "$target_ssid" == "$active_ssid" ]]; then
            notify-send -u low -i network-wireless-symbolic "Wi-Fi" "Already connected to $target_ssid"
            exit 0
        fi

        # Check if saved connection exists
        if nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "$target_ssid"; then
            notify-send -u low -i network-wireless-symbolic "Wi-Fi" "Connecting to $target_ssid..."
            if nmcli connection up id "$target_ssid"; then
                notify-send -u normal -i network-wireless-symbolic "Wi-Fi" "Connected to $target_ssid"
            else
                notify-send -u critical -i network-error-symbolic "Wi-Fi" "Failed to connect to $target_ssid"
            fi
        else
            # New connection: check if password required
            if echo "$chosen" | grep -q "🔒"; then
                pass=$(rofi -dmenu -password -theme "$MINIMAL_ROOT/rofi/selector.rasi" \
                    -theme-str "$("$MINIMAL_ROOT/scripts/rofi-images.sh" selector 2>/dev/null || "$MINIMAL_ROOT/scripts/theme.sh" --rofi 2>/dev/null || true)" \
                    -p "Password for $target_ssid: " 2>/dev/null || true)
                [[ -n "$pass" ]] || exit 0
                notify-send -u low -i network-wireless-symbolic "Wi-Fi" "Connecting to $target_ssid..."
                if nmcli device wifi connect "$target_ssid" password "$pass"; then
                    notify-send -u normal -i network-wireless-symbolic "Wi-Fi" "Connected to $target_ssid"
                else
                    notify-send -u critical -i network-error-symbolic "Wi-Fi" "Connection failed: check password"
                fi
            else
                notify-send -u low -i network-wireless-symbolic "Wi-Fi" "Connecting to $target_ssid..."
                if nmcli device wifi connect "$target_ssid"; then
                    notify-send -u normal -i network-wireless-symbolic "Wi-Fi" "Connected to $target_ssid"
                else
                    notify-send -u critical -i network-error-symbolic "Wi-Fi" "Failed to connect to $target_ssid"
                fi
            fi
        fi
        ;;
esac
