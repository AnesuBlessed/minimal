#!/usr/bin/env bash
# Hyprland calls this once per login. Every persistent process is a native binary.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
mkdir -p -- "$MINIMAL_CACHE" "$MINIMAL_STATE" "$MINIMAL_RUNTIME"
export MINIMAL_WALLPAPER="$MINIMAL_ROOT/wallpapers/japan_lake.jpg"
if [[ -r $MINIMAL_STATE/current_wallpaper ]]; then
    read -r selected < "$MINIMAL_STATE/current_wallpaper"
    [[ ! -f $selected ]] || MINIMAL_WALLPAPER=$selected
fi
export MINIMAL_WALLPAPER
# Failure to prepare frost never prevents the locker/idle daemon from starting.
"$MINIMAL_ROOT/scripts/prepare-lock.sh" "$MINIMAL_WALLPAPER" >>"$MINIMAL_CACHE/session.log" 2>&1 &
if [[ -x /usr/lib/hyprpolkitagent/hyprpolkitagent ]]; then
    /usr/lib/hyprpolkitagent/hyprpolkitagent >>"$MINIMAL_CACHE/session.log" 2>&1 &
elif [[ -x /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 ]]; then
    /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 >>"$MINIMAL_CACHE/session.log" 2>&1 &
fi
# Hardware auto-detection & environment configuration
"$MINIMAL_ROOT/scripts/hardware-detect.sh" >>"$MINIMAL_CACHE/session.log" 2>&1 || true
if [[ -f "$MINIMAL_CACHE/hardware.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$MINIMAL_CACHE/hardware.env"
    set +a
fi

# D-Bus & Systemd Desktop Portal Integration (Screen sharing & file pickers)
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland LIBVA_DRIVER_NAME VDPAU_DRIVER AMD_VULKAN_ICD __GLX_VENDOR_LIBRARY_NAME NVD_BACKEND ELECTRON_OZONE_PLATFORM_HINT >>"$MINIMAL_CACHE/session.log" 2>&1 || true
systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP LIBVA_DRIVER_NAME VDPAU_DRIVER AMD_VULKAN_ICD __GLX_VENDOR_LIBRARY_NAME NVD_BACKEND ELECTRON_OZONE_PLATFORM_HINT >>"$MINIMAL_CACHE/session.log" 2>&1 || true
systemctl --user restart xdg-desktop-portal-hyprland xdg-desktop-portal >>"$MINIMAL_CACHE/session.log" 2>&1 || true

# GNOME Keyring Integration (Auto-unlock secrets, passwords, SSH keys)
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
    eval "$(gnome-keyring-daemon --start --components=secrets,ssh,pks11 2>/dev/null)" || true
    export SSH_AUTH_SOCK
    dbus-update-activation-environment --systemd SSH_AUTH_SOCK >>"$MINIMAL_CACHE/session.log" 2>&1 || true
fi

# USB Removable Drive Integration (Auto-mounting & desktop notifications)
if command -v udiskie >/dev/null 2>&1; then
    udiskie --no-tray --notify --automount >>"$MINIMAL_CACHE/session.log" 2>&1 &
fi

# Background Low-Battery & Critical-Battery Protection
"$MINIMAL_ROOT/scripts/battery-monitor.sh" >>"$MINIMAL_CACHE/session.log" 2>&1 &

foot --server >>"$MINIMAL_CACHE/session.log" 2>&1 &
waybar -c "$MINIMAL_ROOT/waybar/config.jsonc" -s "$MINIMAL_ROOT/waybar/style.css" >>"$MINIMAL_CACHE/session.log" 2>&1 &
printf '%s\n' "$!" > "$MINIMAL_RUNTIME/waybar.pid"
mako --config "$MINIMAL_ROOT/mako/config" >>"$MINIMAL_CACHE/session.log" 2>&1 &
hyprpaper --config "$MINIMAL_ROOT/hypr/hyprpaper.conf" >>"$MINIMAL_CACHE/session.log" 2>&1 &
hypridle --config "$MINIMAL_ROOT/hypr/hypridle.conf" >>"$MINIMAL_CACHE/session.log" 2>&1 &
wl-paste --type text --watch cliphist store >>"$MINIMAL_CACHE/session.log" 2>&1 &
wl-paste --type image --watch cliphist store >>"$MINIMAL_CACHE/session.log" 2>&1 &
exit 0
