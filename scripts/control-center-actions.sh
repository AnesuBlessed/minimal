#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — FAST DIRECT ACTION HANDLER (ZERO PYTHON OVERHEAD)
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

act="${1:-}"
shift || true

case "$act" in
    audio-volume)
        pct="${1:-50}"
        wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 2>/dev/null || true
        exec wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ "${pct}%"
        ;;
    audio-mute)
        exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        ;;
    mic-volume)
        pct="${1:-50}"
        wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0 2>/dev/null || true
        exec wpctl set-volume @DEFAULT_AUDIO_SOURCE@ "${pct}%"
        ;;
    mic-mute)
        exec wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
        ;;
    audio-set-sink)
        exec wpctl set-default "${1:-}"
        ;;
    audio-set-source)
        exec wpctl set-default "${1:-}"
        ;;
    brightness)
        pct="${1:-50}"
        exec brightnessctl --class=backlight set "${pct}%"
        ;;
    caffeine-toggle)
        exec "$MINIMAL_ROOT/scripts/caffeine.sh" toggle
        ;;
    nightlight-toggle)
        exec "$MINIMAL_ROOT/scripts/night-light.sh"
        ;;
    dnd-toggle)
        exec "$MINIMAL_ROOT/scripts/notifications.sh" dnd
        ;;
    wifi-toggle)
        cur=$(nmcli -t -f WIFI radio 2>/dev/null || echo "enabled")
        if [[ "$cur" == "enabled" ]]; then
            exec nmcli radio wifi off
        else
            exec nmcli radio wifi on
        fi
        ;;
    wifi-scan)
        exec nmcli device wifi rescan
        ;;
    wifi-connect)
        ssid="${1:-}"
        pw="${2:-}"
        if [[ -n "$pw" ]]; then
            nmcli device wifi connect "$ssid" password "$pw"
        else
            nmcli connection up id "$ssid" 2>/dev/null || nmcli device wifi connect "$ssid"
        fi
        command -v notify-send >/dev/null 2>&1 && notify-send -a minimal "Wi-Fi Connected" "$ssid" || true
        ;;
    wifi-disconnect)
        ssid="${1:-}"
        [[ -n "$ssid" ]] && exec "$MINIMAL_ROOT/scripts/network-action.py" disconnect "$ssid"
        ;;
    wifi-forget)
        ssid="${1:-}"
        if [[ -n "$ssid" ]]; then
            nmcli connection delete id "$ssid" 2>/dev/null || true
            command -v notify-send >/dev/null 2>&1 && notify-send -a minimal "Removed Saved Network" "$ssid" || true
        fi
        ;;
    wifi-hotspot)
        active=$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep -i ':.*wireless' | cut -d: -f1 || true)
        if [[ "$active" =~ [Hh]otspot ]]; then
            nmcli connection down id Hotspot 2>/dev/null || true
            command -v notify-send >/dev/null 2>&1 && notify-send -a minimal "Wi-Fi Hotspot Stopped" "Restored normal Wi-Fi client mode" || true
        else
            nmcli device wifi hotspot 2>/dev/null || true
            command -v notify-send >/dev/null 2>&1 && notify-send -a minimal "Wi-Fi Hotspot Active" "Hotspot started" || true
        fi
        ;;
    airplane-toggle)
        cur_wifi=$(nmcli -t -f WIFI radio 2>/dev/null || echo "disabled")
        cur_bt=$(bluetoothctl show 2>/dev/null || true)
        if [[ "$cur_wifi" == "enabled" || "$cur_bt" =~ "Powered: yes" ]]; then
            nmcli radio all off 2>/dev/null || true
            bluetoothctl power off 2>/dev/null || true
            rfkill block bluetooth 2>/dev/null || true
            command -v notify-send >/dev/null 2>&1 && notify-send -a minimal "Airplane Mode Enabled" "Wi-Fi and Bluetooth turned off" || true
        else
            rfkill unblock all 2>/dev/null || true
            sleep 0.15
            nmcli radio all on 2>/dev/null || true
            bluetoothctl power on 2>/dev/null || true
            bluetoothctl discoverable-timeout 0 2>/dev/null || true
            bluetoothctl pairable on 2>/dev/null || true
            bluetoothctl discoverable on 2>/dev/null || true
            command -v notify-send >/dev/null 2>&1 && notify-send -a minimal "Airplane Mode Disabled" "Wireless radios restored" || true
        fi
        ;;
    bt-toggle)
        cur=$(bluetoothctl show 2>/dev/null || true)
        if [[ "$cur" =~ "Powered: yes" ]]; then
            exec bluetoothctl power off
        else
            rfkill unblock bluetooth 2>/dev/null || true
            bluetoothctl power on 2>/dev/null || true
            bluetoothctl discoverable-timeout 0 2>/dev/null || true
            bluetoothctl pairable on 2>/dev/null || true
            exec bluetoothctl discoverable on
        fi
        ;;
    bt-discoverable)
        cur=$(bluetoothctl show 2>/dev/null || true)
        target="on"
        [[ "$cur" =~ "Discoverable: yes" ]] && target="off"
        bluetoothctl discoverable-timeout 0 2>/dev/null || true
        bluetoothctl pairable on 2>/dev/null || true
        exec bluetoothctl discoverable "$target"
        ;;
    bt-scan)
        exec bluetoothctl --timeout 4 scan on
        ;;
    bt-pair)
        mac="${1:-}"
        if [[ -n "$mac" ]]; then
            if bluetoothctl pair "$mac"; then
                bluetoothctl trust "$mac" 2>/dev/null || true
                bluetoothctl connect "$mac" 2>/dev/null || true
                command -v notify-send >/dev/null 2>&1 && notify-send -a minimal "Bluetooth Paired" "$mac" || true
            else
                command -v notify-send >/dev/null 2>&1 && notify-send -a minimal -u critical "Bluetooth Pairing Failed" "$mac" || true
            fi
        fi
        ;;
    bt-connect)
        mac="${1:-}"
        if [[ -n "$mac" ]]; then
            if bluetoothctl connect "$mac"; then
                command -v notify-send >/dev/null 2>&1 && notify-send -a minimal "Bluetooth Connected" "$mac" || true
            else
                command -v notify-send >/dev/null 2>&1 && notify-send -a minimal -u critical "Bluetooth Connection Failed" "$mac" || true
            fi
        fi
        ;;
    bt-disconnect)
        mac="${1:-}"
        if [[ -n "$mac" ]]; then
            bluetoothctl disconnect "$mac" 2>/dev/null || true
            command -v notify-send >/dev/null 2>&1 && notify-send -a minimal "Bluetooth Disconnected" "$mac" || true
        fi
        ;;
    bt-trust)
        mac="${1:-}"
        info=$(bluetoothctl info "$mac" 2>/dev/null || true)
        cmd="trust"
        [[ "$info" =~ "Trusted: yes" ]] && cmd="untrust"
        exec bluetoothctl "$cmd" "$mac"
        ;;
    bt-forget)
        mac="${1:-}"
        if [[ -n "$mac" ]]; then
            bluetoothctl remove "$mac" 2>/dev/null || true
            command -v notify-send >/dev/null 2>&1 && notify-send -a minimal "Bluetooth Device Removed" "$mac" || true
        fi
        ;;
    bt-send)
        mac="${1:-}"
        exec "$MINIMAL_ROOT/scripts/bluetooth-send.py" ${mac:+"$mac"}
        ;;
    *)
        exit 1
        ;;
esac
