#!/usr/bin/env bash
# Back up every affected entry before changing any; preserve original symlinks.
set -Eeuo pipefail
umask 077
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SOURCE_DIR/scripts/deployment-common.sh"
parse_options "$@"
[[ -z $SELECTED_BACKUP ]] || fail '--backup belongs to restore.sh'

missing=()
for binary in Hyprland hyprctl waybar fuzzel foot footclient mako makoctl hyprpaper hypridle hyprlock wpctl brightnessctl notify-send quickshell jq magick python3 wl-paste wl-copy cliphist flock loginctl; do
    command -v "$binary" >/dev/null 2>&1 || missing+=("$binary")
done
if ((${#missing[@]})); then fail "Install required commands before deployment: ${missing[*]}"; fi
python3 -c 'from PIL import Image' || fail 'Install python-pillow'
for comp in "${COMPONENTS[@]}"; do [[ -d $(source_for "$comp") ]] || fail "Missing source: $comp"; done
Hyprland --verify-config -c "$SOURCE_DIR/hypr/hyprland.lua" >/dev/null || fail 'Hyprland configuration validation failed'
fuzzel --check-config --config "$SOURCE_DIR/fuzzel/fuzzel.ini" || fail 'Fuzzel configuration validation failed'
foot --check-config -c "$SOURCE_DIR/foot/foot.ini" || fail 'Foot configuration validation failed'
if $CHECK_ONLY; then
    printf 'Preflight passed. Would install %s into %s\n' "${COMPONENTS[*]}" "$CONFIG_DIR"
    exit 0
fi
lock_deployment
all_linked=true
for comp in "${COMPONENTS[@]}"; do
    [[ -L $CONFIG_DIR/$comp && $(readlink -- "$CONFIG_DIR/$comp") == "$(source_for "$comp")" ]] || all_linked=false
done
if $all_linked; then printf 'Already deployed; existing backups retained.\n'; exit 0; fi
mkdir -p -- "$BACKUP_BASE"
TXN=$(mktemp -d "$BACKUP_BASE/minimal-$(date +%Y%m%d_%H%M%S_%N)-XXXXXXXX")
mkdir -- "$TXN/original" "$TXN/displaced" "$TXN/interrupted" "$TXN/created"
printf '%s\n' "$CONFIG_DIR" > "$TXN/config-dir"
printf 'preparing\n' > "$TXN/status"
# A copy failure ends here, before any live entry is moved or removed.
for comp in "${COMPONENTS[@]}"; do
    src=$(source_for "$comp")
    if exists "$CONFIG_DIR/$comp"; then
        cp -a -- "$CONFIG_DIR/$comp" "$TXN/original/$comp"
        printf '%s\tpresent\t%s\n' "$comp" "$src" >> "$TXN/manifest.tsv"
    else
        printf '%s\tabsent\t%s\n' "$comp" "$src" >> "$TXN/manifest.tsv"
    fi
done
CHANGED=(); COMMITTED=false
trap transaction_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
printf 'installing\n' > "$TXN/status"
for comp in "${COMPONENTS[@]}"; do
    CHANGED+=("$comp")
    if exists "$CONFIG_DIR/$comp"; then mv -T -- "$CONFIG_DIR/$comp" "$TXN/displaced/$comp"; fi
    # Journal before creating: a signal between these steps remains recoverable.
    touch "$TXN/created/$comp"
    ln -s -- "$(source_for "$comp")" "$CONFIG_DIR/$comp"
done
printf 'installed\n' > "$TXN/status"
COMMITTED=true
printf 'Installed. Backup: %s\nLog out and choose Hyprland to start Minimal. Roll back with ./restore.sh\n' "$TXN"
