#!/usr/bin/env bash
# =============================================================================
#  MINIMAL RICE — FASTFETCH CHARACTER SELECTOR / RANDOMIZER
# =============================================================================

set -euo pipefail

ASSETS_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")/fastfetch/assets"
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
mkdir -p -- "$MINIMAL_STATE"
TARGET="$MINIMAL_STATE/fastfetch.png"

case "${1:-}" in
    "random")
        CHAR=$(find "$ASSETS_DIR" -type f -name "*.png" ! -name "current.png" | shuf -n 1)
        if [[ -n "$CHAR" ]]; then
            ln -sf -- "$CHAR" "$TARGET"
            echo "Fastfetch character set to: $(basename "$CHAR" .png)"
        fi
        ;;
    "list")
        echo "Available anime character assets:"
        find "$ASSETS_DIR" -type f -name "*.png" ! -name "current.png" -exec basename {} .png \; | sort
        ;;
    *)
        if [[ -n "${1:-}" && ! "${1:-}" =~ [/\\] && -f "$ASSETS_DIR/$1.png" ]]; then
            ln -sf -- "$ASSETS_DIR/$1.png" "$TARGET"
            echo "Fastfetch character set to: $1"
        else
            echo "Usage: $0 [<character_name>|random|list]" >&2
            exit 2
        fi
        ;;
esac
