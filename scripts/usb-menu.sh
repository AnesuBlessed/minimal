#!/usr/bin/env bash
# Enumerate mounted removable/USB volumes, then select by index rather than label.
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/paths.sh"
volumes=$(lsblk --json --paths --output PATH,RM,TRAN,MOUNTPOINTS | jq -r '
    def volumes($parent):
        ($parent or .rm == true or .rm == 1 or .tran == "usb") as $removable |
        (if $removable then .mountpoints[]? | select(type == "string" and length > 0) else empty end),
        (.children[]? | volumes($removable));
    [.blockdevices[] | volumes(false)] | unique[]')
if [[ -z $volumes ]]; then
    notify-send -a minimal-usb "USB Drives" "No mounted removable drives detected."
    exit 0
fi
mapfile -t media_dirs <<< "$volumes"
items=()
for dir in "${media_dirs[@]}"; do
    items+=("📂  Open: $dir" "⏏  Unmount: $dir")
done
chosen=$(printf '%s\n' "${items[@]}" | fuzzel --dmenu --index \
    --config "$MINIMAL_ROOT/fuzzel/fuzzel.ini" --prompt "USB Drive: " --lines 8 --width 36) || exit 0
[[ $chosen =~ ^[0-9]+$ ]] && ((chosen < ${#items[@]})) || exit 0
dir=${media_dirs[chosen / 2]}
if ((chosen % 2 == 0)); then
    for fm in dolphin thunar nautilus nemo pcmanfm pcmanfm-qt xdg-open; do
        if command -v "$fm" >/dev/null 2>&1; then
            exec "$fm" "$dir"
        fi
    done
    notify-send -a minimal-usb "USB Drives" "No file manager installed to open $dir"
    exit 1
fi
if command -v udiskie-umount >/dev/null 2>&1; then
    udiskie-umount "$dir"
else
    device=$(findmnt --first-only --noheadings --output SOURCE --mountpoint "$dir")
    udisksctl unmount --block-device "$device"
fi
notify-send -a minimal-usb "Volume unmounted" "$dir"
