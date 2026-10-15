#!/usr/bin/env bash
# =============================================================================
#  MINIMAL RICE — FASTFETCH CHARACTER SELECTOR / RANDOMIZER
# =============================================================================

ASSETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fastfetch/assets" && pwd)"
TARGET="$ASSETS_DIR/current.png"

case "$1" in
    "random")
        CHAR=$(find "$ASSETS_DIR" -type f -name "*.png" ! -name "current.png" | shuf -n 1)
        if [ -n "$CHAR" ]; then
            ln -sf "$(basename "$CHAR")" "$TARGET"
            echo "Fastfetch character set to: $(basename "$CHAR" .png)"
        fi
        ;;
    "list")
        echo "Available anime character assets:"
        find "$ASSETS_DIR" -type f -name "*.png" ! -name "current.png" -exec basename {} .png \;
        ;;
    *)
        if [ -f "$ASSETS_DIR/$1.png" ]; then
            ln -sf "$1.png" "$TARGET"
            echo "Fastfetch character set to: $1"
        else
            echo "Usage: $0 [ryuzaki|pochita|agk_clan|aisaka|geass|loli|random|list]"
        fi
        ;;
esac
