#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — SESSION STARTUP
# =============================================================================
#  Launched once when Hyprland starts. Keeps background daemons lean and
#  self-contained: polkit, mako, waybar, hypridle, hyprpaper, cliphist,
#  foot server, network-manager applet, and blueman applet.
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
mkdir -p -- "$MINIMAL_CACHE" "$MINIMAL_STATE" "$MINIMAL_RUNTIME"

# 1. D-Bus & Systemd Portal Integration
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland || true
systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP || true

# 2. Polkit Authentication Agent
if command -v hyprpolkitagent >/dev/null 2>&1 && ! pgrep -x hyprpolkitagent >/dev/null; then
    hyprpolkitagent &
elif [[ -x /usr/lib/hyprpolkitagent/hyprpolkitagent ]] && ! pgrep -x hyprpolkitagent >/dev/null; then
    /usr/lib/hyprpolkitagent/hyprpolkitagent &
elif command -v lxpolkit >/dev/null 2>&1 && ! pgrep -x lxpolkit >/dev/null; then
    lxpolkit &
fi

# 3. Notification Daemon (Mako)
if command -v mako >/dev/null 2>&1 && ! pgrep -x mako >/dev/null; then
    mako --config "$MINIMAL_ROOT/mako/config" &
fi

# 4. Status Bar (Waybar)
if command -v waybar >/dev/null 2>&1 && ! pgrep -x waybar >/dev/null; then
    waybar --config "$MINIMAL_ROOT/waybar/config.jsonc" --style "$MINIMAL_ROOT/waybar/style.css" &
fi

# 5. Idle Management (Hypridle)
if command -v hypridle >/dev/null 2>&1 && ! pgrep -x hypridle >/dev/null; then
    hypridle --config "$MINIMAL_ROOT/hypr/hypridle.conf" &
fi

# 6. Wallpaper Daemon (Hyprpaper)
if command -v hyprpaper >/dev/null 2>&1 && ! pgrep -x hyprpaper >/dev/null; then
    hyprpaper --config "$MINIMAL_ROOT/hypr/hyprpaper.conf" &
    # Allow socket to initialize, then apply wallpaper
    (sleep 0.5 && "$MINIMAL_ROOT/scripts/wallpaper.sh") &
fi

# 7. Clipboard History Watcher (Cliphist)
if command -v cliphist >/dev/null 2>&1; then
    pgrep -f "wl-paste.*cliphist" >/dev/null || {
        wl-paste --type text --watch cliphist store &
        wl-paste --type image --watch cliphist store &
    }
fi

# 8. Terminal Server (foot server for zero-latency footclient spawns)
if command -v foot >/dev/null 2>&1 && ! pgrep -x foot >/dev/null; then
    foot --server &
fi

# 9. Battle-Tested Network & Bluetooth Tray Applets
if command -v nm-applet >/dev/null 2>&1 && ! pgrep -x nm-applet >/dev/null; then
    nm-applet --indicator &
fi

if command -v blueman-applet >/dev/null 2>&1 && ! pgrep -x blueman-applet >/dev/null; then
    blueman-applet &
fi

exit 0
