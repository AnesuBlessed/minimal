#!/usr/bin/env bash
# =============================================================================
#  MINIMAL RICE — SAFE DEPLOYMENT SCRIPT
# =============================================================================
#  Adheres strictly to Rule 6 (Non-Destructive Deployment):
#  - Automatically creates a timestamped backup before touching ~/.config
#  - Creates clean atomic symlinks to ~/Projects/minimal/
#  - Completely reversible via ./restore.sh
# =============================================================================

set -e

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config"
BACKUP_DIR="$CONFIG_DIR/backups/backup_pre_minimal_$(date +%Y%m%d_%H%M%S)"

echo "=== Minimal Rice Deployment ==="
echo "Source: $SOURCE_DIR"
echo "Target: $CONFIG_DIR"
echo ""

# 1. Dependency Check
echo "[1/4] Checking required packages..."
MISSING_PKGS=()
for pkg in fuzzel foot mako awww quickshell brightnessctl; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo "  > Warning: Missing packages: ${MISSING_PKGS[*]}"
    echo "  > Run: sudo pacman -S --needed ${MISSING_PKGS[*]}"
else
    echo "  > All core binaries are installed."
fi
echo ""

# 2. Safe Timestamped Backup
echo "[2/4] Backing up existing configurations to $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"

COMPONENTS=("hypr" "waybar" "fuzzel" "foot" "mako" "dunst" "fastfetch")

for comp in "${COMPONENTS[@]}"; do
    if [ -e "$CONFIG_DIR/$comp" ] || [ -L "$CONFIG_DIR/$comp" ]; then
        echo "  > Backing up $comp..."
        cp -rL "$CONFIG_DIR/$comp" "$BACKUP_DIR/$comp" 2>/dev/null || mv "$CONFIG_DIR/$comp" "$BACKUP_DIR/$comp"
        rm -rf "$CONFIG_DIR/$comp"
    fi
done
echo "  > Backup complete."
echo ""

# 3. Create Clean Symlinks
echo "[3/4] Linking minimal configurations..."
for comp in "${COMPONENTS[@]}"; do
    if [ -d "$SOURCE_DIR/$comp" ]; then
        ln -sfn "$SOURCE_DIR/$comp" "$CONFIG_DIR/$comp"
        echo "  > Linked $comp -> $CONFIG_DIR/$comp"
    fi
done
echo ""

# 4. Finalizing
echo "[4/4] Deployment complete!"
echo "  > To test Hyprland: hyprctl reload"
echo "  > To test Waybar: killall waybar && waybar &"
echo "  > To roll back at any time: ./restore.sh"
echo "==============================="
