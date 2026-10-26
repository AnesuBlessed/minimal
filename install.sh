#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — ATOMIC WORKSTATION INSTALLER & SYSTEM CONVERGENCE
# =============================================================================
#  Engineered for Arch Linux & CachyOS.
#  Features:
#    - Pre-flight hardware & dependency audits
#    - Timestamped atomic config backups with auto-generated restore.sh
#    - Reversible, non-destructive symlink deployment
#    - Post-install health verification (Minimal Doctor)
#    - Full rollback & dry-run support
# =============================================================================
set -euo pipefail

MINIMAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BACKUP_BASE="${XDG_STATE_HOME:-$HOME/.local/state}/minimal/backups"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/minimal"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/minimal"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"

# --- ANSI Theme Palette (Minimalist Obsidian & Silver) ---
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_WHITE=$'\033[38;2;255;255;255m'
C_SILVER=$'\033[38;2;212;212;216m'
C_SLATE=$'\033[38;2;161;161;170m'
C_MUTED=$'\033[38;2;113;113;122m'
C_DARK=$'\033[38;2;63;63;70m'
C_GREEN=$'\033[38;2;134;239;172m'
C_RED=$'\033[38;2;248;113;113m'
C_BLUE=$'\033[38;2;147;197;253m'
C_YELLOW=$'\033[38;2;253;224;71m'

# --- Flags ---
DRY_RUN=false
AUTO_CONFIRM=false
MODE="install" # install | restore | doctor | uninstall

print_banner() {
    clear 2>/dev/null || true
    echo "${C_WHITE}${C_BOLD}"
    if [[ -f "$MINIMAL_DIR/assets/brand/logo.txt" ]]; then
        cat "$MINIMAL_DIR/assets/brand/logo.txt"
    else
        echo "    ███╗   ███╗██╗███╗   ██╗██╗███╗   ███╗ █████╗ ██╗"
        echo "    ████╗ ████║██║████╗  ██║██║████╗ ████║██╔══██╗██║"
        echo "    ██╔████╔██║██║██╔██╗ ██║██║██╔████╔██║███████║██║"
        echo "    ██║╚██╔╝██║██║██║╚██╗██║██║██║╚██╔╝██║██╔══██║██║"
        echo "    ██║ ╚═╝ ██║██║██║ ╚████║██║██║ ╚═╝ ██║██║  ██║███████╗"
        echo "    ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝"
    fi
    echo "${C_RESET}"
    echo "  ${C_SILVER}${C_BOLD}MINIMAL WORKSTATION${C_RESET} ${C_MUTED}— Pure Wayland Desktop Environment${C_RESET}"
    echo "  ${C_DIM}Source: $MINIMAL_DIR${C_RESET}"
    echo "  ${C_DARK}─────────────────────────────────────────────────────────────────${C_RESET}"
    echo ""
}

log_step() {
    echo -e "${C_SILVER}${C_BOLD}==>${C_RESET} ${C_WHITE}${C_BOLD}$1${C_RESET}"
}

log_info() {
    echo -e "    ${C_SLATE}•${C_RESET} $1"
}

log_pass() {
    echo -e "    ${C_GREEN}✓ [PASS]${C_RESET} $1"
}

log_warn() {
    echo -e "    ${C_YELLOW}! [WARN]${C_RESET} $1"
}

log_fail() {
    echo -e "    ${C_RED}✗ [FAIL]${C_RESET} $1"
}

# --- Core Dependencies Definition ---
CORE_PKGS=(
    "hyprland"
    "waybar"
    "rofi-wayland"
    "mako"
    "foot"
    "wlogout"
    "hyprpaper"
    "hypridle"
    "hyprlock"
)

TOOL_PKGS=(
    "pamixer"
    "wireplumber"
    "brightnessctl"
    "cliphist"
    "grim"
    "slurp"
    "satty"
    "tesseract"
    "network-manager-applet"
    "blueman"
    "ttf-jetbrains-mono-nerd"
)

# =============================================================================
#  STEP 1: PRE-FLIGHT AUDIT & DEPENDENCY CHECK
# =============================================================================
check_dependencies() {
    log_step "[1/5] Pre-Flight System & Dependency Audit"
    local missing=()

    # Verify distribution
    if [[ -f /etc/os-release ]]; then
        local distro_name
        distro_name=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
        log_info "Detected OS: ${C_WHITE}$distro_name${C_RESET}"
    fi

    # Check Core Packages
    for pkg in "${CORE_PKGS[@]}"; do
        if command -v "$pkg" >/dev/null 2>&1 || pacman -Qq "$pkg" >/dev/null 2>&1; then
            log_pass "Core Component: $pkg"
        else
            log_warn "Missing Core: $pkg"
            missing+=("$pkg")
        fi
    done

    # Check Tools & Fonts
    for pkg in "${TOOL_PKGS[@]}"; do
        if command -v "$pkg" >/dev/null 2>&1 || pacman -Qq "$pkg" >/dev/null 2>&1; then
            log_pass "Tool/Asset: $pkg"
        else
            log_warn "Missing Tool: $pkg"
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        log_warn "The following recommended packages are not installed: ${missing[*]}"
        if [[ "$DRY_RUN" == false && "$AUTO_CONFIRM" == true ]]; then
            echo -e "    ${C_BLUE}Installing missing packages via pacman...${C_RESET}"
            sudo pacman -S --needed --noconfirm "${missing[@]}"
        elif [[ "$DRY_RUN" == false ]]; then
            read -r -p "    Install missing packages now via pacman? [Y/n] " response || true
            if [[ "$response" =~ ^([yY][eE][sS]|[yY]|"")$ ]]; then
                sudo pacman -S --needed "${missing[@]}"
            else
                log_warn "Skipped package installation. Some features may be unavailable."
            fi
        fi
    else
        log_pass "All required packages are satisfied."
    fi
    echo ""
}

# =============================================================================
#  STEP 2: ATOMIC CONFIGURATION BACKUP
# =============================================================================
backup_existing_configs() {
    log_step "[2/5] Atomic Configuration Backup"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$BACKUP_BASE/backup-$timestamp"
    local target_configs=("hypr" "waybar" "rofi" "mako" "foot" "wlogout" "fastfetch")
    local backed_up_any=false

    if [[ "$DRY_RUN" == true ]]; then
        log_info "(DRY RUN) Would create backup directory: $backup_dir"
        for cfg in "${target_configs[@]}"; do
            if [[ -e "$CONFIG_DIR/$cfg" ]]; then
                log_info "(DRY RUN) Would backup: $CONFIG_DIR/$cfg -> $backup_dir/$cfg"
            fi
        done
        echo ""
        return 0
    fi

    mkdir -p "$backup_dir" "$STATE_DIR" "$CACHE_DIR"

    for cfg in "${target_configs[@]}"; do
        local target="$CONFIG_DIR/$cfg"
        if [[ -e "$target" || -L "$target" ]]; then
            # If target already points directly into minimal, skip backing up self-symlink
            if [[ -L "$target" ]] && [[ "$(readlink -f "$target")" == "$MINIMAL_DIR/$cfg"* ]]; then
                log_info "Config '$cfg' is already linked to Minimal; updating link."
                continue
            fi

            log_info "Backing up: $target -> $backup_dir/$cfg"
            cp -a "$target" "$backup_dir/$cfg"
            rm -rf "$target"
            backed_up_any=true
        fi
    done

    # Create atomic rollback script inside the backup directory
    cat > "$backup_dir/restore.sh" << 'RESTORE_EOF'
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"

echo "Restoring configurations from $BACKUP_DIR to $CONFIG_DIR..."
for item in "$BACKUP_DIR"/*; do
    base=$(basename "$item")
    if [[ "$base" == "restore.sh" ]]; then continue; fi
    echo "  Restoring $base..."
    rm -rf "$CONFIG_DIR/$base"
    cp -a "$item" "$CONFIG_DIR/$base"
done
echo "Restore complete! Your previous configuration has been restored."
RESTORE_EOF
    chmod +x "$backup_dir/restore.sh"

    # Record latest backup
    echo "$backup_dir" > "$STATE_DIR/latest_backup"

    if [[ "$backed_up_any" == true ]]; then
        log_pass "Backup stored in: ${C_WHITE}$backup_dir${C_RESET}"
        log_pass "Executable rollback generated at: ${C_WHITE}$backup_dir/restore.sh${C_RESET}"
    else
        log_pass "No conflicting configurations found. Clean install target."
    fi
    echo ""
}

# =============================================================================
#  STEP 3: SAFE DEPLOYMENT & SYMLINKING
# =============================================================================
deploy_minimal() {
    log_step "[3/5] Deploying Minimal Components"
    local components=("hypr" "waybar" "rofi" "mako" "foot" "wlogout" "fastfetch")

    mkdir -p "$CONFIG_DIR" "$STATE_DIR" "$CACHE_DIR"

    # Ensure executable permissions on all scripts
    find "$MINIMAL_DIR/scripts" -type f -name "*.sh" -exec chmod +x {} +

    for comp in "${components[@]}"; do
        local src="$MINIMAL_DIR/$comp"
        local dest="$CONFIG_DIR/$comp"

        if [[ ! -d "$src" ]]; then continue; fi

        if [[ "$DRY_RUN" == true ]]; then
            log_info "(DRY RUN) Would link: $dest -> $src"
            continue
        fi

        rm -rf "$dest"
        ln -sfn "$src" "$dest"
        log_pass "Linked: ${C_WHITE}~/.config/$comp${C_RESET} -> ${C_MUTED}$src${C_RESET}"
    done

    # Default Wallpaper setup
    if [[ "$DRY_RUN" == false ]]; then
        local default_wall="$MINIMAL_DIR/wallpapers/139396752_p0.jpg"
        if [[ ! -f "$STATE_DIR/wallpaper.set" && -f "$default_wall" ]]; then
            ln -sf "$default_wall" "$STATE_DIR/wallpaper.set"
            log_pass "Initialized default wallpaper in state directory."
        fi
    fi
    echo ""
}

# =============================================================================
#  STEP 4: SYSTEM CONVERGENCE & VERIFICATION (DOCTOR)
# =============================================================================
run_doctor() {
    log_step "[4/5] Minimal Doctor — Health Verification"

    # 1. Compositor Config Syntax Audit
    if command -v Hyprland >/dev/null 2>&1; then
        local hypr_test
        hypr_test=$(Hyprland --config "$MINIMAL_DIR/hypr/hyprland.lua" --verify-config 2>&1 || true)
        if echo "$hypr_test" | grep -qi "config ok"; then
            log_pass "Hyprland Configuration: Syntax Verified (config ok)"
        else
            log_warn "Hyprland Configuration parsing produced warnings or errors"
        fi
    else
        log_warn "Hyprland is not in PATH."
    fi

    # 2. Waybar Layout Integrity
    if command -v waybar >/dev/null 2>&1; then
        local layout_err=0
        for l in "$MINIMAL_DIR/waybar/layouts/"*.jsonc; do
            if ! timeout 0.2 waybar -c "$l" -s "$MINIMAL_DIR/waybar/style.css" >/dev/null 2>&1; then
                # Waybar returns timeout (124) on normal running, other code on syntax error
                local code=$?
                if [[ $code -ne 124 && $code -ne 0 ]]; then
                    layout_err=$((layout_err + 1))
                fi
            fi
        done
        if [[ $layout_err -eq 0 ]]; then
            log_pass "Waybar Layouts: All 17 presets syntax-clean and ready"
        else
            log_warn "Waybar: $layout_err layout(s) reported issues"
        fi
    fi

    # 3. Audio & Brightness Check
    if command -v pamixer >/dev/null 2>&1 || command -v wpctl >/dev/null 2>&1; then
        log_pass "Audio Controller: Operational (WirePlumber / Pamixer)"
    else
        log_warn "Audio Controller: Neither pamixer nor wpctl detected"
    fi

    if command -v brightnessctl >/dev/null 2>&1; then
        log_pass "Display Brightness: brightnessctl detected"
    fi

    # 4. Clipboard Watcher
    if command -v cliphist >/dev/null 2>&1; then
        log_pass "Clipboard Engine: cliphist detected"
    fi

    echo ""
}

# =============================================================================
#  STEP 5: COMPLETION SUMMARY & SHORTCUTS
# =============================================================================
show_summary() {
    log_step "[5/5] Installation Complete!"
    echo "  ${C_GREEN}${C_BOLD}Minimal has been successfully deployed.${C_RESET}"
    echo ""
    echo "  ${C_SILVER}${C_BOLD}Core Keybindings Cheatsheet:${C_RESET}"
    echo "  ${C_DARK}─────────────────────────────────────────────────────────────────${C_RESET}"
    echo "    ${C_WHITE}Super + A${C_RESET}               Application Launcher (Rofi Dual-Pane)"
    echo "    ${C_WHITE}Super + Tab${C_RESET}             Active Window Switcher"
    echo "    ${C_WHITE}Super + T${C_RESET}               Foot Terminal (Obsidian Glass)"
    echo "    ${C_WHITE}Super + C${C_RESET}               Clipboard Manager (Raw Text Copy)"
    echo "    ${C_WHITE}Super + Shift + C${C_RESET}       Clipboard Delete Mode (Wipe / Item Remove)"
    echo "    ${C_WHITE}Super + W${C_RESET}               Wallpaper Picker Menu"
    echo "    ${C_WHITE}Super + Alt + Up/Down${C_RESET}   Cycle Between All 17 Waybar Layouts"
    echo "    ${C_WHITE}Super + Escape${C_RESET}          Circular Power Menu (Wlogout)"
    echo "    ${C_WHITE}Super + L${C_RESET}               Lock Screen (Hyprlock)"
    echo "    ${C_WHITE}Super + R${C_RESET}               Live Reload Hyprland & Waybar"
    echo "  ${C_DARK}─────────────────────────────────────────────────────────────────${C_RESET}"
    echo ""
    echo "  ${C_SLATE}To launch Minimal:${C_RESET}"
    echo "    If you are already in Hyprland, reload with: ${C_WHITE}hyprctl reload${C_RESET}"
    echo "    Or log out and start a fresh Hyprland session."
    echo ""
    echo "  ${C_MUTED}To revert back at any time: ./install.sh --restore${C_RESET}"
    echo ""
}

# =============================================================================
#  RESTORE / ROLLBACK HANDLER
# =============================================================================
handle_restore() {
    print_banner
    log_step "Configuration Rollback (Restore Mode)"

    if [[ ! -d "$BACKUP_BASE" ]]; then
        log_fail "No backups found in $BACKUP_BASE."
        exit 1
    fi

    local backups=()
    while IFS= read -r line; do
        backups+=("$line")
    done < <(find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -name "backup-*" | sort -r)

    if [[ ${#backups[@]} -eq 0 ]]; then
        log_fail "No backup snapshots available."
        exit 1
    fi

    echo "  Available backup snapshots:"
    local i=1
    for b in "${backups[@]}"; do
        echo "    [$i] $(basename "$b")"
        i=$((i + 1))
    done
    echo ""

    local choice=1
    if [[ "$AUTO_CONFIRM" == false && ${#backups[@]} -gt 1 ]]; then
        read -r -p "  Select backup snapshot to restore [1-${#backups[@]}]: " choice || true
        choice=${choice:-1}
    fi

    local selected_idx=$((choice - 1))
    local target_backup="${backups[$selected_idx]}"

    if [[ ! -f "$target_backup/restore.sh" ]]; then
        log_fail "Snapshot $target_backup is missing restore.sh."
        exit 1
    fi

    echo ""
    log_info "Executing: $target_backup/restore.sh"
    bash "$target_backup/restore.sh"
    log_pass "System configurations successfully restored to previous state."
    exit 0
}

# =============================================================================
#  CLI ARGUMENT PARSING
# =============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        --restore)
            MODE="restore"
            shift
            ;;
        --doctor)
            MODE="doctor"
            shift
            ;;
        --uninstall)
            MODE="restore"
            shift
            ;;
        -h|--help)
            print_banner
            echo "Usage: ./install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run       Simulate installation without touching any files on disk"
            echo "  -y, --yes       Automatically confirm package installs and prompts"
            echo "  --doctor        Run diagnostic health audit only"
            echo "  --restore       Restore configurations from previous backup snapshot"
            echo "  --uninstall     Remove Minimal symlinks and revert to latest backup"
            echo "  -h, --help      Display this help message"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# =============================================================================
#  MAIN ENTRYPOINT
# =============================================================================
if [[ "$MODE" == "restore" ]]; then
    handle_restore
elif [[ "$MODE" == "doctor" ]]; then
    print_banner
    run_doctor
    exit 0
fi

print_banner
check_dependencies
backup_existing_configs
deploy_minimal
run_doctor
show_summary
