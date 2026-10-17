#!/usr/bin/env bash
# =============================================================================
#  MINIMAL RICE — FASTFETCH CHARACTER SELECTOR / RANDOMIZER
# =============================================================================

set -euo pipefail

ASSETS_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")/fastfetch/assets"
TARGET="$ASSETS_DIR/current.png"

case "${1:-}" in
    "random")
        CHAR=$(find "$ASSETS_DIR" -type f -name "*.png" ! -name "current.png" | shuf -n 1)
        if [[ -n "$CHAR" ]]; then
            ln -sf -- "$(basename "$CHAR")" "$TARGET"
            echo "Fastfetch character set to: $(basename "$CHAR" .png)"
        fi
        ;;
    "list")
        echo "Available anime character assets:"
        find "$ASSETS_DIR" -type f -name "*.png" ! -name "current.png" -exec basename {} .png \; | sort
        ;;
    *)
        if [[ -n "${1:-}" && ! "${1:-}" =~ [/\\] && -f "$ASSETS_DIR/$1.png" ]]; then
            ln -sf -- "$1.png" "$TARGET"
            echo "Fastfetch character set to: $1"
        else
            echo "Usage: $0 [ryuzaki|pochita|agk_clan|aisaka|geass|loli|random|list]" >&2
            exit 2
        fi
        ;;
esac
