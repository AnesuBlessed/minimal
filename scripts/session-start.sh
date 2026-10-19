#!/usr/bin/env bash
# Hyprland calls this once per login. Native systemd owns daemon lifetimes.
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
    eval "$(gnome-keyring-daemon --start --components=secrets,ssh,pkcs11 2>/dev/null)" || true
    export SSH_AUTH_SOCK
    dbus-update-activation-environment --systemd SSH_AUTH_SOCK >>"$MINIMAL_CACHE/session.log" 2>&1 || true
fi

# Scope units to this compositor instance; repeated startup is idempotent.
prefix="$MINIMAL_SERVICE_PREFIX"
"$MINIMAL_ROOT/scripts/session-conflicts.py" >>"$MINIMAL_CACHE/session.log" 2>&1 || true
start_service() {
    local name=$1; shift
    systemctl --user is-active --quiet "$prefix-$name.service" && return 0
    systemd-run --user --quiet --collect --unit="$prefix-$name" \
        --property=PartOf=graphical-session.target --property=Restart=on-failure \
        --setenv="WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}" \
        --setenv="HYPRLAND_INSTANCE_SIGNATURE=${HYPRLAND_INSTANCE_SIGNATURE:-}" \
        --setenv="MINIMAL_ROOT=$MINIMAL_ROOT" --setenv="MINIMAL_CACHE=$MINIMAL_CACHE" \
        --setenv="MINIMAL_WALLPAPER=$MINIMAL_WALLPAPER" --setenv="MINIMAL_STATE=$MINIMAL_STATE" --setenv="MINIMAL_RUNTIME=$MINIMAL_RUNTIME" \
        "$@"
}
if [[ -x /usr/lib/hyprpolkitagent/hyprpolkitagent ]] && ! pgrep -u "$(id -u)" -x hyprpolkitagent >/dev/null; then
    start_service polkit /usr/lib/hyprpolkitagent/hyprpolkitagent
fi
# Lock/suspend integration must not depend on optional native helper compilation.
start_service mako mako --config "$MINIMAL_ROOT/mako/config"
"$MINIMAL_ROOT/scripts/idle-config.sh" generate
start_service hypridle hypridle --config "$MINIMAL_STATE/hypridle.conf"
start_service bt-agent "$MINIMAL_ROOT/scripts/bluetooth-agent.py"
systemctl --user start obex.service >>"$MINIMAL_CACHE/session.log" 2>&1 || true
if "$MINIMAL_ROOT/scripts/build-native.sh"; then
    compositor_pid=$(hyprctl -j instances | jq -r --arg instance "${HYPRLAND_INSTANCE_SIGNATURE:-}" '.[] | select(.instance == $instance) | .pid')
    if [[ $compositor_pid =~ ^[0-9]+$ ]]; then
        start_service guard "$MINIMAL_CACHE/bin/session-guard" "$compositor_pid" "$prefix"
    fi
    start_service automount "$MINIMAL_CACHE/bin/automount"
else
    notify-send -a minimal -u critical 'Session helpers unavailable' 'Automatic USB mounting and session cleanup could not start; locking remains enabled.' || true
fi
# Shell runs only for each bounded check; the waiting timer is native systemd.
if ! systemctl --user is-active --quiet "$prefix-battery.timer"; then
    systemd-run --user --quiet --collect --unit="$prefix-battery" \
        --on-active=30s --on-unit-active=60s --timer-property=PartOf=graphical-session.target \
        "$MINIMAL_ROOT/scripts/battery-monitor.sh" --check
fi
if [[ ! -S ${XDG_RUNTIME_DIR:-/nonexistent}/foot-${WAYLAND_DISPLAY:-none}.sock ]]; then
    start_service foot foot --server
fi
start_service waybar "$MINIMAL_ROOT/scripts/waybar.sh" --start
start_service hyprpaper hyprpaper --config "$MINIMAL_ROOT/hypr/hyprpaper.conf"
"$MINIMAL_ROOT/scripts/restore-wallpapers.sh" >>"$MINIMAL_CACHE/session.log" 2>&1 &
start_service clipboard-text wl-paste --type text --watch cliphist store
start_service clipboard-image wl-paste --type image --watch cliphist store
python3 "$MINIMAL_ROOT/scripts/control-center-backend.py" --state >>"$MINIMAL_CACHE/session.log" 2>&1 &
exit 0
