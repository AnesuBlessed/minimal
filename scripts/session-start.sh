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
# MINIMAL_ROOT is exported so D-Bus/systemd-activated helpers (e.g. a
# hypridle.service) can still resolve lock.sh.
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland MINIMAL_ROOT || true
systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP MINIMAL_ROOT || true

# 2. Idle Management (Hypridle) — first, so idle/sleep locking never depends
#    on anything below succeeding.
if command -v hypridle >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x hypridle >/dev/null; then
    hypridle --config "$MINIMAL_ROOT/hypr/hypridle.conf" &
fi

# 3. Polkit Authentication Agent
if command -v hyprpolkitagent >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x hyprpolkitagent >/dev/null; then
    hyprpolkitagent &
elif [[ -x /usr/lib/hyprpolkitagent/hyprpolkitagent ]] && ! pgrep -u "$(id -u)" -x hyprpolkitagent >/dev/null; then
    /usr/lib/hyprpolkitagent/hyprpolkitagent &
elif command -v lxpolkit >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x lxpolkit >/dev/null; then
    lxpolkit &
fi

# 4. Notification Daemon (Mako)
if command -v mako >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x mako >/dev/null; then
    mako_config="$MINIMAL_ROOT/mako/config"
    [[ ! -f "$MINIMAL_STATE/theme/mako.conf" ]] || mako_config="$MINIMAL_STATE/theme/mako.conf"
    mako --config "$mako_config" &
fi

# 5. Status Bar (Waybar) — a bar failure must not abort the rest of the session.
if command -v waybar >/dev/null 2>&1; then
    if ! "$MINIMAL_ROOT/scripts/bar.sh" start; then
        notify-send -u critical "Minimal" "Waybar failed to start; see $MINIMAL_STATE/waybar.log" 2>/dev/null || true
    fi
fi

# 6. Wallpaper Daemon (Hyprpaper)
if command -v hyprpaper >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x hyprpaper >/dev/null; then
    systemctl --user start hyprpaper.service 2>/dev/null || hyprpaper --config "$MINIMAL_ROOT/hypr/hyprpaper.conf" &
    # Allow socket to initialize, then apply wallpaper
    (sleep 0.5 && "$MINIMAL_ROOT/scripts/wallpaper.sh") &
fi

# 7. Clipboard History Watcher (Cliphist)
if command -v cliphist >/dev/null 2>&1 && command -v wl-paste >/dev/null 2>&1; then
    for kind in text image; do
        if ! pgrep -u "$(id -u)" -f "^wl-paste --type $kind --watch cliphist store$" >/dev/null; then
            wl-paste --type "$kind" --watch cliphist store &
        fi
    done
fi

# 8. Terminal Server (foot server for zero-latency footclient spawns)
if command -v foot >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -f "^foot --server" >/dev/null; then
    foot_config="$MINIMAL_ROOT/foot/foot.ini"
    [[ ! -f "$MINIMAL_STATE/theme/foot.ini" ]] || foot_config="$MINIMAL_STATE/theme/foot.ini"
    foot --server --config "$foot_config" &
fi

# 9. Battle-Tested Network & Bluetooth Tray Applets
if command -v nm-applet >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x nm-applet >/dev/null; then
    nm-applet --indicator &
fi

if command -v blueman-applet >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x blueman-applet >/dev/null; then
    blueman-applet &
fi

exit 0
