#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — REMOVABLE USB DRIVE MANAGER & SAFE REMOVAL MENU
# =============================================================================
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"

media_dirs=()
# Standard Arch/systemd/udisks mount paths
for base in "/run/media/$USER" "/run/media/${LOGNAME:-}" "/media"; do
    [[ -d "$base" ]] || continue
    while IFS= read -r -d '' dir; do
        [[ -d "$dir" ]] && media_dirs+=("$dir")
    done < <(find "$base" -mindepth 1 -maxdepth 2 -type d -print0 2>/dev/null)
done

# If no mounted media directories found, check for any mounted RM=1 devices via lsblk
if ((${#media_dirs[@]} == 0)); then
    notify-send -a minimal-usb -i drive-removable-media -t 3000 \
        "󱊞  USB Drives" "No mounted removable drives detected."
    exit 0
fi

menu_items=""
for dir in "${media_dirs[@]}"; do
    name=$(basename "$dir")
    menu_items+="⏏  Eject: $name ($dir)\n📂  Open: $name in Dolphin\n"
done

chosen=$(printf '%b' "$menu_items" | fuzzel --dmenu \
    --config "$MINIMAL_ROOT/fuzzel/fuzzel.ini" \
    --prompt "󱊞  USB Drive: " \
    --lines $(( ${#media_dirs[@]} * 2 )) \
    --width 36 2>/dev/null) || exit 0

[[ -n "$chosen" ]] || exit 0

if [[ "$chosen" == *"Open:"* ]]; then
    target=$(echo "$chosen" | sed -n 's/.*Open: [^ ]* in Dolphin.*//; s/.*(\(.*\)).*/\1/p')
    # Fallback extraction: grab directory path from between parentheses or matching media_dirs
    for dir in "${media_dirs[@]}"; do
        if [[ "$chosen" == *"$dir"* ]]; then
            exec dolphin "$dir"
        fi
    done
elif [[ "$chosen" == *"Eject:"* ]]; then
    for dir in "${media_dirs[@]}"; do
        if [[ "$chosen" == *"$dir"* ]]; then
            name=$(basename "$dir")
            if command -v udiskie-umount >/dev/null 2>&1; then
                udiskie-umount "$dir" >/dev/null 2>&1 || udisksctl unmount -p "$dir" >/dev/null 2>&1 || umount "$dir"
            elif command -v udisksctl >/dev/null 2>&1; then
                udisksctl unmount -p "$dir" >/dev/null 2>&1 || umount "$dir"
            else
                umount "$dir"
            fi
            notify-send -a minimal-usb -i drive-removable-media -t 4000 \
                "󱊞  Safe to Remove" "Drive '$name' was safely unmounted."
            exit 0
        fi
    done
fi
