#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — WALLPAPER PACK DOWNLOADER & SYNC
# =============================================================================
#  Downloads or links the full 2.5 GB wallpaper collection (1,300+ wallpapers
#  across 12 categories: Anime, Catppuccin, Cyberpunk, Gruvbox, Monochrome,
#  Nature, Nord, Tokyo-Night, etc.) to ~/.local/share/minimal/wallpapers.
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

DEST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/minimal/wallpapers"
LOCAL_DOCS="${HOME}/Documents/Wallpapers"
REPO_URL="https://github.com/AnesuBlessed/minimal-wallpapers.git"

mkdir -p -- "$(dirname "$DEST_DIR")"

echo "=== Minimal Wallpaper Pack ==="

# 1. Local sync if user already has Documents/Wallpapers
if [[ -d "$LOCAL_DOCS" && ! -d "$DEST_DIR" ]]; then
    echo "Found local collection at $LOCAL_DOCS."
    ln -sfn -- "$LOCAL_DOCS" "$DEST_DIR"
    echo "✓ Linked $LOCAL_DOCS -> $DEST_DIR"
    exit 0
fi

if [[ -d "$DEST_DIR" && -n "$(ls -A "$DEST_DIR" 2>/dev/null)" ]]; then
    echo "Wallpaper pack is already installed at $DEST_DIR."
    exit 0
fi

# 2. Remote download if not already linked
echo "Downloading full wallpaper pack from $REPO_URL..."
if command -v git >/dev/null 2>&1; then
    git clone --depth=1 "$REPO_URL" "$DEST_DIR"
    echo "✓ Full wallpaper pack installed to $DEST_DIR."
else
    echo "Error: git is required to download the wallpaper pack." >&2
    exit 1
fi
