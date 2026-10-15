#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — COMPOSITOR & SYSTEM ENVIRONMENT INSTALLER
# =============================================================================
#  - Standalone, zero-bloat dynamic tiling environment for Hyprland
#  - HyDE-inspired visual styling, interactive progress, and atomic rollback
#  - Automatic environment isolation: purges conflicting hooks and daemons
# =============================================================================
set -Eeuo pipefail
umask 077

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SOURCE_DIR/scripts/deployment-common.sh"
parse_options "$@"
[[ -z $SELECTED_BACKUP ]] || fail '--backup belongs to restore.sh'

# --- ANSI Styling & Helpers (HyDE Compatible) ---
C_CYAN=$'\e[38;2;188;184;239m'
C_WHITE=$'\e[38;2;244;244;245m'
C_MUTED=$'\e[38;2;130;130;146m'
C_GREEN=$'\e[38;2;166;227;161m'
C_YELLOW=$'\e[38;2;249;226;175m'
C_RED=$'\e[38;2;243;139;168m'
C_BOLD=$'\e[1m'
C_RESET=$'\e[0m'

print_banner() {
    cat <<EOF
${C_CYAN}
         ▓▒       ░▓                                                          
        ░█▓░     ░██▒                                                         
        ▒██▓▒   ░██▓▓                                                         
        ▒███▓▒ ░████▓                                                         
        ▒█▒▓█▓░██▓▒▓▓       ${C_BOLD}${C_WHITE}█   █▄  █  █  █▄  ▄█   ▄▀▀▄   █${C_RESET}${C_CYAN}                   
        ░█░ ▓▓▓██░ ▓▓       ${C_BOLD}${C_WHITE}█   █ █ █  █  █ ▀▀ █  █▄▄▄█   █${C_RESET}${C_CYAN}                   
        ░█▒ ░███▒  █▓       ${C_BOLD}${C_WHITE}█   █  ▀█  █  █    █  █   █   █${C_RESET}${C_CYAN}                   
        ░█▒ ██▓▒▒░ █▓       ${C_BOLD}${C_WHITE}█   █   █  █  █    █  █   █   ████▄${C_RESET}${C_CYAN}               
        ░█▒▓██ ▒█▓▒▓▒                                                         
        ░█▓█▓   ▒█▓▓░                                                         
        ░██▓     ▒██▒                                                         
         ▓▓       ▒▓░                                                         
${C_RESET}
   ${C_MUTED}────────────────────────────────────────────────────────────────────────${C_RESET}
    ${C_BOLD}${C_WHITE}MINIMAL${C_RESET} :: Pure Dynamic Tiling Environment for Hyprland
    ${C_MUTED}Zero-bloat, event-driven, hardware-accelerated, 100% standalone${C_RESET}
   ${C_MUTED}────────────────────────────────────────────────────────────────────────${C_RESET}
EOF
}

log_step() {
    local step=$1; shift
    printf '\n\e[30;46m STEP %s \e[0m %b\n' "$step" "$*"
}

log_ok() {
    printf '   %b[✓]%b %s\n' "$C_GREEN" "$C_RESET" "$*"
}

log_info() {
    printf '   %b[::]%b %s\n' "$C_CYAN" "$C_RESET" "$*"
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

missing=()
for binary in Hyprland hyprctl waybar wlogout fuzzel foot footclient mako makoctl hyprpaper hypridle hyprlock wpctl brightnessctl notify-send quickshell jq magick python3 wl-paste wl-copy cliphist flock loginctl; do
    if command -v "$binary" >/dev/null 2>&1; then
        :
    else
        missing+=("$binary")
    fi
done

if ((${#missing[@]})); then
    fail "Install required commands before deployment: ${missing[*]}"
fi
log_ok "All required binaries verified"

python3 -c 'from PIL import Image' || fail 'Install python-pillow'
log_ok "Python Pillow library verified"

for comp in "${COMPONENTS[@]}"; do
    [[ -d $(source_for "$comp") ]] || fail "Missing source: $comp"
done
log_ok "All component source directories present"

Hyprland --verify-config -c "$SOURCE_DIR/hypr/hyprland.lua" >/dev/null || fail 'Hyprland configuration validation failed'
log_ok "Hyprland native Lua config validated"

fuzzel --check-config --config "$SOURCE_DIR/fuzzel/fuzzel.ini" || fail 'Fuzzel configuration validation failed'
log_ok "Fuzzel launcher config validated"

foot --check-config -c "$SOURCE_DIR/foot/foot.ini" || fail 'Foot terminal config validated'
log_ok "Foot terminal config validated"

if $CHECK_ONLY; then
    printf 'Preflight passed. Would install %s into %s\n' "${COMPONENTS[*]}" "$CONFIG_DIR"
    exit 0
fi

# --- Lock Deployment Process ---
lock_deployment

# Check if already deployed
all_linked=true
for comp in "${COMPONENTS[@]}"; do
    [[ -L $CONFIG_DIR/$comp && $(readlink -- "$CONFIG_DIR/$comp") == "$(source_for "$comp")" ]] || all_linked=false
done
if $all_linked; then
    printf '\n%b[i]%b Already deployed; existing backups retained.\n' "$C_CYAN" "$C_RESET"
    exit 0
fi

# --- 2. Isolation & Hook Neutralization ---
log_step "2/5" "${C_BOLD}System Isolation & Hook Neutralization${C_RESET}"

# Register standalone Wayland session for SDDM / GDM / greetd / Ly
sessions_dir="${XDG_DATA_HOME:-$HOME/.local/share}/wayland-sessions"
mkdir -p -- "$sessions_dir"
if [[ -f $SOURCE_DIR/assets/minimal.desktop ]]; then
    cp -f "$SOURCE_DIR/assets/minimal.desktop" "$sessions_dir/minimal.desktop" 2>/dev/null || true
    log_ok "Registered standalone Wayland session ($sessions_dir/minimal.desktop)"
fi

# Neutralize any shell hooks that force foreign compositor configs
for hook in "$CONFIG_DIR"/fish/conf.d/*.fish "$CONFIG_DIR"/environment.d/*.conf; do
    if [[ -f $hook ]] && grep -q "HYPRLAND_CONFIG" "$hook" 2>/dev/null; then
        mv -f "$hook" "${hook}.disabled" 2>/dev/null || true
        log_ok "Disabled conflicting compositor hook ($(basename "$hook"))"
    fi
done

# Stop any competing systemd transient bar or notification services
if command -v systemctl >/dev/null 2>&1; then
    for svc in $(systemctl --user list-units --type=service --state=running --no-legend 2>/dev/null | awk '{print $1}' | grep -E 'bar|notification|waybar|dunst|swaync' || true); do
        systemctl --user stop "$svc" 2>/dev/null || true
    done
    log_ok "Cleaned up competing user systemd services"
fi

# Clear hijacked session environment variables
unset HYPRLAND_CONFIG SWAYSOCK || true
log_ok "Ensured clean, rice-agnostic Hyprland session entry point"

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

# Ensure user avatar exists; provide fallback from repo
if [[ ! -f $HOME/.face.icon && ! -f $HOME/.face && -f $SOURCE_DIR/wallpapers/default-avatar.png ]]; then
    cp -f "$SOURCE_DIR/wallpapers/default-avatar.png" "$HOME/.face.icon" 2>/dev/null || true
    log_ok "Set up default lockscreen avatar ($HOME/.face.icon)"
fi

# Pre-generate blurred lock screen wallpaper
initial_wall="$SOURCE_DIR/wallpapers/japan_lake.jpg"
if [[ -f $initial_wall ]]; then
    "$SOURCE_DIR/scripts/prepare-lock.sh" "$initial_wall" 2>/dev/null || true
    log_ok "Pre-generated lock screen backdrop cache"
fi

# Auto-detect GPU hardware & populate hardware.env
if [[ -x $SOURCE_DIR/scripts/hardware-detect.sh ]]; then
    "$SOURCE_DIR/scripts/hardware-detect.sh" 2>/dev/null || true
    log_ok "Detected GPU hardware and generated hardware.env"
fi

# --- Installation Summary ---
cat <<EOF

   ${C_GREEN}${C_BOLD}✔ Minimal Installation Successfully Completed!${C_RESET}
   ${C_MUTED}────────────────────────────────────────────────────────────────────────${C_RESET}
    ${C_BOLD}Backup Archive :${C_RESET} $TXN
    ${C_BOLD}Target Config  :${C_RESET} $CONFIG_DIR
    ${C_BOLD}Session Mode   :${C_RESET} Standalone Hyprland (100% HyDE-free)

    ${C_BOLD}Essential Keybindings:${C_RESET}
      • ${C_CYAN}Super + Q${C_RESET}          : Foot Terminal
      • ${C_CYAN}Super + Space${C_RESET}      : Fuzzel Application Launcher
      • ${C_CYAN}Super + Backspace${C_RESET}  : Power Menu (wlogout)
      • ${C_CYAN}Super + L${C_RESET}          : Lock Screen (Hyprlock)
      • ${C_CYAN}Super + W${C_RESET}          : Wallpaper Selector (Carousel)
      • ${C_CYAN}Super + C${C_RESET}          : Close Active Window

    ${C_MUTED}To revert anytime: ./restore.sh --backup "$TXN"${C_RESET}
   ${C_MUTED}────────────────────────────────────────────────────────────────────────${C_RESET}
EOF
exit 0
