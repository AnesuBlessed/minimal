#!/usr/bin/env bash
# =============================================================================
#  MINIMAL RICE — ROLLBACK & RESTORATION SCRIPT
# =============================================================================
#  Restores the most recent backup from ~/.config/backups/
# =============================================================================

set -e

CONFIG_DIR="$HOME/.config"
BACKUP_BASE="$CONFIG_DIR/backups"

if [ ! -d "$BACKUP_BASE" ]; then
    echo "No backups directory found at $BACKUP_BASE"
    exit 1
fi

LATEST_BACKUP=$(ls -td "$BACKUP_BASE"/backup_pre_minimal_* 2>/dev/null | head -n 1)

if [ -z "$LATEST_BACKUP" ] || [ ! -d "$LATEST_BACKUP" ]; then
    echo "No previous backup archives found in $BACKUP_BASE"
    exit 1
fi

echo "=== Rolling Back Configurations ==="
echo "Restoring from: $LATEST_BACKUP"
echo ""

COMPONENTS=("hypr" "waybar" "fuzzel" "foot" "mako" "fastfetch")

for comp in "${COMPONENTS[@]}"; do
    if [ -d "$LATEST_BACKUP/$comp" ]; then
        rm -rf "$CONFIG_DIR/$comp"
        cp -r "$LATEST_BACKUP/$comp" "$CONFIG_DIR/$comp"
        echo "  > Restored $comp"
    fi
done

echo ""
echo "Rollback successfully completed!"
echo "Run 'hyprctl reload' to restore previous session state."
echo "==================================="
