#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — COMPOSITOR & SYSTEM ENVIRONMENT INSTALLER
# =============================================================================
#  - Standalone, zero-bloat dynamic tiling environment for Hyprland
#  - Minimal visual styling, interactive progress, and atomic rollback
#  - Session-scoped environment isolation and reversible registration
# =============================================================================
set -Eeuo pipefail
umask 077

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SOURCE_DIR/scripts/deployment-common.sh"
parse_options "$@"
[[ -z $SELECTED_BACKUP ]] || fail '--backup belongs to restore.sh'

# --- ANSI Styling & Helpers (Minimal Theme Palette) ---
C_ACCENT=$'\e[38;2;208;135;112m'
C_CYAN=$'\e[38;2;208;135;112m'
C_WHITE=$'\e[38;2;236;239;244m'
C_MUTED=$'\e[38;2;148;156;173m'
C_GREEN=$'\e[38;2;163;190;140m'
C_YELLOW=$'\e[38;2;235;203;139m'
C_RED=$'\e[38;2;191;97;106m'
C_BADGE=$'\e[38;2;20;22;27;48;2;208;135;112;1m'
C_BOLD=$'\e[1m'
C_RESET=$'\e[0m'

print_banner() {
    cat <<EOF

  ${C_ACCENT}███╗   ███╗ ██╗ ███╗   ██╗ ██╗ ███╗   ███╗  █████╗  ██╗${C_RESET}
  ${C_ACCENT}████╗ ████║ ██║ ████╗  ██║ ██║ ████╗ ████║ ██╔══██╗ ██║${C_RESET}
  ${C_WHITE}██╔████╔██║ ██║ ██╔██╗ ██║ ██║ ██╔████╔██║ ███████║ ██║${C_RESET}
  ${C_WHITE}██║╚██╔╝██║ ██║ ██║╚██╗██║ ██║ ██║╚██╔╝██║ ██╔══██║ ██║${C_RESET}
  ${C_ACCENT}██║ ╚═╝ ██║ ██║ ██║ ╚████║ ██║ ██║ ╚═╝ ██║ ██║  ██║ ███████╗${C_RESET}
  ${C_MUTED}╚═╝     ╚═╝ ╚═╝ ╚═╝  ╚═══╝ ╚═╝ ╚═╝     ╚═╝ ╚═╝  ╚═╝ ╚══════╝${C_RESET}

  ${C_MUTED}╭──────────────────────────────────────────────────────────────╮${C_RESET}
  ${C_MUTED}│${C_RESET}  ${C_BOLD}${C_WHITE}MINIMAL${C_RESET} ${C_MUTED}·${C_RESET} ${C_ACCENT}Native Dynamic Tiling Environment for Hyprland${C_RESET}    ${C_MUTED}│${C_RESET}
  ${C_MUTED}│${C_RESET}  ${C_MUTED}Zero-bloat · Event-driven · Hardware-aware · Transactional${C_RESET}  ${C_MUTED}│${C_RESET}
  ${C_MUTED}╰──────────────────────────────────────────────────────────────╯${C_RESET}
EOF
}

log_step() {
    local step=$1; shift
    printf '\n  %b STEP %s %b %b\n' "$C_BADGE" "$step" "$C_RESET" "$*"
}

log_ok() {
    printf '   %b[✓]%b %s\n' "$C_GREEN" "$C_RESET" "$*"
}

log_info() {
    printf '   %b[::]%b %s\n' "$C_ACCENT" "$C_RESET" "$*"
}

log_warn() {
    printf '   %b[!]%b %s\n' "$C_YELLOW" "$C_RESET" "$*"
}

# --- Show Banner ---
if ! $CHECK_ONLY; then
    print_banner
fi

# --- 1. Preflight Validation ---
log_step "1/5" "${C_BOLD}Preflight Dependencies & Binary Validation${C_RESET}"

declare -A PKG_MAP=(
    [Hyprland]="hyprland"
    [hyprctl]="hyprland"
    [waybar]="waybar"
    [wlogout]="wlogout"
    [fuzzel]="fuzzel"
    [foot]="foot"
    [footclient]="foot"
    [mako]="mako"
    [makoctl]="mako"
    [hyprpaper]="hyprpaper"
    [hypridle]="hypridle"
    [hyprlock]="hyprlock"
    [wpctl]="wireplumber"
    [brightnessctl]="brightnessctl"
    [notify-send]="libnotify"
    [quickshell]="quickshell"
    [jq]="jq"
    [magick]="imagemagick"
    [python3]="python"
    [wl-paste]="wl-clipboard"
    [wl-copy]="wl-clipboard"
    [cliphist]="cliphist"
    [flock]="util-linux"
    [loginctl]="systemd"
    [fastfetch]="fastfetch"
    [cc]="gcc"
    [pkg-config]="pkgconf"
    [gio]="glib2"
    [curl]="curl"
    [file]="file"
    [setsid]="util-linux"
    [ffmpeg]="ffmpeg"
    [grim]="grim"
    [slurp]="slurp"
    [satty]="satty"
    [udisksctl]="udisks2"
    [nm-applet]="network-manager-applet"
    [nm-connection-editor]="nm-connection-editor"
    [blueman-manager]="blueman"
    [pavucontrol]="pavucontrol"
    [checkupdates]="pacman-contrib"
    [playerctl]="playerctl"
)

missing=()
# Required: the session cannot start, lock, or build its helpers without these.
for binary in Hyprland hyprctl waybar wlogout fuzzel foot mako makoctl hyprpaper hypridle hyprlock wpctl brightnessctl notify-send quickshell jq magick python3 wl-paste wl-copy cliphist flock loginctl cc pkg-config gio setsid; do
    if command -v "$binary" >/dev/null 2>&1; then
        :
    else
        missing+=("$binary")
    fi
done

packages_to_install=()
for bin in "${missing[@]}"; do
    pkg="${PKG_MAP[$bin]:-$bin}"
    if [[ ! " ${packages_to_install[*]} " =~ " ${pkg} " ]]; then
        packages_to_install+=("$pkg")
    fi
done

if ! python3 -c 'from PIL import Image' >/dev/null 2>&1; then
    if [[ ! " ${packages_to_install[*]} " =~ " python-pillow " ]]; then
        packages_to_install+=("python-pillow")
    fi
fi

# The automounter requires the native GIO UDisks backend, not udiskie.
if command -v pacman >/dev/null 2>&1 && ! pacman -Q gvfs >/dev/null 2>&1; then
    packages_to_install+=(gvfs)
fi
# Check the font independently of whether another binary is missing.
if ! fc-match "JetBrainsMono Nerd Font" -f "%{family}" 2>/dev/null | grep -Fq "JetBrainsMono Nerd Font"; then
    if [[ ! " ${packages_to_install[*]} " =~ " ttf-jetbrains-mono-nerd " ]]; then
        packages_to_install+=("ttf-jetbrains-mono-nerd")
    fi
fi

# Install feature dependencies too, including on already-deployed systems.
declare -A OPTIONAL_FEATURES=(
    [mpvpaper]="video wallpaper|mpvpaper"
    [hyprsunset]="night light|hyprsunset"
    [gnome-keyring-daemon]="secret storage|gnome-keyring"
    [nm-applet]="network tray|network-manager-applet"
    [nm-connection-editor]="network settings|nm-connection-editor"
    [blueman-manager]="Bluetooth settings|blueman"
    [pavucontrol]="audio settings|pavucontrol"
    [footclient]="foot server (terminal falls back to plain foot)|foot"
    [fastfetch]="terminal system summary|fastfetch"
    [grim]="screenshots|grim"
    [slurp]="region screenshots|slurp"
    [satty]="screenshot annotation|satty"
    [ffmpeg]="video wallpaper thumbnails|ffmpeg"
    [curl]="wallpaper web search|curl"
    [file]="wallpaper web search validation|file"
    [udisksctl]="USB eject menu|udisks2"
    [inotifywait]="instant pause/resume of wallpaper search|inotify-tools"
    [playerctl]="media keys|playerctl"
    [checkupdates]="Waybar update counter|pacman-contrib"
)
for binary in mpvpaper hyprsunset gnome-keyring-daemon nm-applet nm-connection-editor blueman-manager pavucontrol footclient fastfetch grim slurp satty ffmpeg curl file udisksctl inotifywait playerctl checkupdates; do
    command -v "$binary" >/dev/null 2>&1 && continue
    feature=${OPTIONAL_FEATURES[$binary]%%|*}
    package=${OPTIONAL_FEATURES[$binary]##*|}
    log_info "Missing '$binary' for $feature; will install $package"
    if [[ ! " ${packages_to_install[*]} " == *" $package "* ]]; then
        packages_to_install+=("$package")
    fi
done

if ((${#packages_to_install[@]})); then
    if $CHECK_ONLY; then
        fail "Install dependency packages before deployment: ${packages_to_install[*]}"
    fi

    log_warn "Missing dependency packages for Minimal: ${packages_to_install[*]}"
    if command -v pacman >/dev/null 2>&1; then
        do_install=false
        if [[ ${AUTO_YES:-false} == true ]]; then
            do_install=true
        elif [[ -t 0 ]]; then
            printf '\n   %b[?]%b Minimal requires these packages to function.\n' "$C_YELLOW" "$C_RESET"
            printf '       Install them now via pacman? [Y/n] '
            if [[ -r /dev/tty ]]; then
                read -r reply </dev/tty || reply="y"
            else
                read -r reply || reply="y"
            fi
            if [[ -z $reply || $reply =~ ^[Yy]$ ]]; then
                do_install=true
            fi
        else
            do_install=true
        fi

        if $do_install; then
            log_info "Elevating permissions to install packages..."
            # Authenticate sudo first to prompt clearly for password
            if sudo -v; then
                log_info "Installing packages with pacman..."
                if sudo pacman -S --needed --noconfirm "${packages_to_install[@]}"; then
                    log_ok "All dependency packages installed successfully"
                else
                    fail "Failed to install dependency packages via pacman. Please install manually: ${packages_to_install[*]}"
                fi
            else
                fail "Sudo authentication failed. Please install dependency packages: ${packages_to_install[*]}"
            fi
        else
            fail "Aborted by user. Please install dependency packages before deployment: ${packages_to_install[*]}"
        fi
    else
        fail "Pacman package manager not detected. Please install dependency packages: ${packages_to_install[*]}"
    fi
fi

log_ok "Dependency installation checks complete"

python3 -c 'from PIL import Image' || fail 'Install python-pillow'
log_ok "Python Pillow library verified"

for comp in "${COMPONENTS[@]}"; do
    [[ -d $(source_for "$comp") ]] || fail "Missing source: $comp"
done
[[ -f $SOURCE_DIR/assets/minimal.desktop ]] || fail 'Missing session template'
log_ok "All component source directories present"

Hyprland --verify-config -c "$SOURCE_DIR/hypr/hyprland.lua" >/dev/null || fail 'Hyprland configuration validation failed'
log_ok "Hyprland native Lua config validated"

fuzzel --check-config --config "$SOURCE_DIR/fuzzel/fuzzel.ini" || fail 'Fuzzel configuration validation failed'
log_ok "Fuzzel launcher config validated"

foot --check-config -c "$SOURCE_DIR/foot/foot.ini" || fail 'Foot terminal configuration validation failed'
log_ok "Foot terminal config validated"

if $CHECK_ONLY; then
    printf 'Preflight passed. Would install %s into %s\n' "${COMPONENTS[*]}" "$CONFIG_DIR"
    exit 0
fi

# Host application data belongs to its owner; isolate the session at launch.
# --- Lock Deployment Process ---
lock_deployment

print_summary_card() {
    local status_title=$1
    local backup_label=$2
    local gpu_line="Auto-detected at login"
    local hw_env="${XDG_CACHE_HOME:-$HOME/.cache}/minimal/hardware.env"
    if [[ -r $hw_env ]]; then
        local parsed_gpu
        parsed_gpu=$(awk -F'GPU: ' '/^#  Platform:/ {print $2; exit}' "$hw_env" 2>/dev/null || true)
        [[ -z $parsed_gpu ]] || gpu_line=$parsed_gpu
    fi
    cat <<EOF

  ${C_MUTED}╭──────────────────────────────────────────────────────────────────────╮${C_RESET}
  ${C_MUTED}│${C_RESET}  ${C_GREEN}${C_BOLD}✔ ${status_title}${C_RESET}
  ${C_MUTED}├──────────────────────────────────────────────────────────────────────┤${C_RESET}
  ${C_MUTED}│${C_RESET}  ${C_BOLD}Target Config  :${C_RESET} ${CONFIG_DIR}
  ${C_MUTED}│${C_RESET}  ${C_BOLD}Backup Archive :${C_RESET} ${backup_label}
  ${C_MUTED}│${C_RESET}  ${C_BOLD}Hardware Tuned :${C_RESET} ${gpu_line}
  ${C_MUTED}│${C_RESET}  ${C_BOLD}Managed Links  :${C_RESET} ${COMPONENTS[*]}
  ${C_MUTED}├──────────────────────────────────────────────────────────────────────┤${C_RESET}
  ${C_MUTED}│${C_RESET}  ${C_BOLD}Essential Shortcuts (Live-parsed from hypr/keybinds.lua):${C_RESET}
  ${C_MUTED}│${C_RESET}    ${C_ACCENT}Super + A${C_RESET}       Application Launcher     ${C_ACCENT}Super + T${C_RESET}   Foot Terminal
  ${C_MUTED}│${C_RESET}    ${C_ACCENT}Super + C${C_RESET}       Clipboard History        ${C_ACCENT}Super + W${C_RESET}   Wallpaper Picker
  ${C_MUTED}│${C_RESET}    ${C_ACCENT}Super + /${C_RESET}       Keybind Cheat-Sheet      ${C_ACCENT}Super + L${C_RESET}   Lock Screen
  ${C_MUTED}│${C_RESET}    ${C_ACCENT}Super + Escape${C_RESET}  Power Menu (wlogout)     ${C_ACCENT}Super + Q${C_RESET}   Close Window
  ${C_MUTED}╰──────────────────────────────────────────────────────────────────────╯${C_RESET}
EOF
}

# Check if already deployed
all_linked=true
for comp in "${COMPONENTS[@]}"; do
    [[ -L $CONFIG_DIR/$comp && $(readlink -- "$CONFIG_DIR/$comp") == "$(source_for "$comp")" ]] || all_linked=false
done
if $all_linked; then
    session_path="${XDG_DATA_HOME:-$HOME/.local/share}/wayland-sessions/minimal.desktop"
    [[ -f $session_path ]] || fail 'Session entry missing; restore then deploy to recreate it transactionally'
    printf '\n%b[i]%b Already deployed; no changes made and existing backups retained.\n' "$C_ACCENT" "$C_RESET"
    print_summary_card "Minimal Session Verified & Active" "Retained in $BACKUP_BASE"
    exit 0
fi

# Required helpers must build successfully before changing managed configuration.
"$SOURCE_DIR/scripts/build-native.sh" || fail 'Native helper build failed; configuration was not changed'

# --- 2. Isolation & Hook Neutralization ---
log_step "2/5" "${C_BOLD}System Isolation & Hook Neutralization${C_RESET}"

# Isolation belongs to session-entry.sh. Installing a second session must not
# rename host shell hooks or stop services in the desktop currently running.
log_info "Standalone entry point isolates compositor variables at login"

# --- 3. Atomic Backup Creation ---
log_step "3/5" "${C_BOLD}Creating Atomic Rollback Snapshot${C_RESET}"
mkdir -p -- "$BACKUP_BASE"
TXN=$(mktemp -d "$BACKUP_BASE/minimal-$(date +%Y%m%d_%H%M%S_%N)-XXXXXXXX")
mkdir -- "$TXN/original" "$TXN/displaced" "$TXN/interrupted" "$TXN/created"
printf '%s\n' "$CONFIG_DIR" > "$TXN/config-dir"
printf 'preparing\n' > "$TXN/status"

for comp in "${COMPONENTS[@]}"; do
    src=$(source_for "$comp")
    if exists "$CONFIG_DIR/$comp"; then
        cp -a -- "$CONFIG_DIR/$comp" "$TXN/original/$comp"
        printf '%s\tpresent\t%s\n' "$comp" "$src" >> "$TXN/manifest.tsv"
        log_info "Backed up existing config: $comp"
    else
        printf '%s\tabsent\t%s\n' "$comp" "$src" >> "$TXN/manifest.tsv"
    fi
done
log_ok "Backup transaction recorded at: $TXN"

CHANGED=(); COMMITTED=false
trap transaction_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# Record session registration in the same transaction as configuration links.
session_path="${XDG_DATA_HOME:-$HOME/.local/share}/wayland-sessions/minimal.desktop"
mkdir -p -- "$(dirname "$session_path")"
snapshot_session "$session_path"
python3 - "$SOURCE_DIR/scripts/session-entry.sh" "$TXN/session-installed" "$CONFIG_DIR" "$SOURCE_DIR/assets/minimal.desktop" <<'PYDESKTOP'
import sys
# Desktop Entry Exec uses its own quoting and percent field-code syntax.
def quote(value):
    # Escape once for Exec tokenization, then for Desktop Entry string parsing.
    value = value.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%')
    return '"' + value.replace('\\', '\\\\') + '"'
command = quote(sys.argv[1]) + ' --config-dir ' + quote(sys.argv[3])
with open(sys.argv[2], 'w') as stream:
    with open(sys.argv[4]) as template:
        for line in template:
            stream.write('Exec=' + command + '\n' if line.startswith('Exec=') else line)
PYDESKTOP
touch "$TXN/session-changed"
cp --remove-destination -- "$TXN/session-installed" "$session_path"

# --- 4. Deploying Managed Symlinks ---
log_step "4/5" "${C_BOLD}Deploying Managed Symlinks${C_RESET}"
printf 'installing\n' > "$TXN/status"

for comp in "${COMPONENTS[@]}"; do
    CHANGED+=("$comp")
    if exists "$CONFIG_DIR/$comp"; then
        mv -T -- "$CONFIG_DIR/$comp" "$TXN/displaced/$comp"
    fi
    touch "$TXN/created/$comp"
    ln -s -- "$(source_for "$comp")" "$CONFIG_DIR/$comp"
    log_ok "Linked $comp -> $CONFIG_DIR/$comp"
done

printf 'installed\n' > "$TXN/status"
COMMITTED=true

# --- 5. Initializing Session Cache & Assets ---
log_step "5/5" "${C_BOLD}Initializing Session Cache & Assets${C_RESET}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/minimal"
mkdir -p -- "$cache_dir"

# Pre-generate blurred lock screen wallpaper
initial_wall="$SOURCE_DIR/wallpapers/japan_lake.jpg"
if [[ -f $initial_wall ]]; then
    if "$SOURCE_DIR/scripts/prepare-lock.sh" "$initial_wall"; then
        log_ok "Pre-generated lock screen backdrop cache"
    else
        log_warn "Lock background preparation failed; locking uses its solid-color fallback"
    fi
fi

# Auto-detect GPU hardware & populate hardware.env
if [[ -x $SOURCE_DIR/scripts/hardware-detect.sh ]]; then
    if "$SOURCE_DIR/scripts/hardware-detect.sh"; then
        log_ok "Detected GPU hardware and generated hardware.env"
    else
        log_warn "Hardware cache generation failed; startup will retry detection"
    fi
fi

# Session activation is explicit; deployment never reloads the running desktop.
print_summary_card "Minimal Installation Successfully Completed!" "$TXN"
printf '  %bTo revert anytime: ./restore.sh --backup "%s"%b\n\n' "$C_MUTED" "$TXN" "$C_RESET"
exit 0
