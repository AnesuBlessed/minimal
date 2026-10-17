#!/usr/bin/env bash
# =============================================================================
#  MINIMAL — BARE-METAL ARCH / CACHYOS BOOTSTRAP
#  Turns a fresh Arch/CachyOS installation into the complete Minimal desktop.
# =============================================================================
set -euo pipefail

ROOT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
DRY_RUN=false
if [[ ${1:-} == --check || ${1:-} == --dry-run ]]; then
    DRY_RUN=true
fi

BASE_PACKAGES=(
    hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpolkitagent
    waybar wlogout fuzzel foot mako hyprpaper hypridle hyprlock
    pipewire wireplumber pipewire-pulse pipewire-alsa
    wl-clipboard cliphist grim slurp satty tesseract tesseract-data-eng
    playerctl brightnessctl imagemagick jq python python-pillow python-gobject
    networkmanager nm-connection-editor bluez bluez-utils
    fastfetch fish ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji
)

detect_gpu_packages() {
    local pci_info
    pci_info=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)
    local pkgs=(mesa)
    if grep -qi 'amd\|radeon' <<< "$pci_info"; then
        pkgs+=(vulkan-radeon libva-mesa-driver)
    fi
    if grep -qi 'intel' <<< "$pci_info"; then
        pkgs+=(vulkan-intel intel-media-driver)
    fi
    if grep -qi 'nvidia' <<< "$pci_info"; then
        pkgs+=(nvidia-utils libva-nvidia-driver)
    fi
    printf '%s\n' "${pkgs[@]}"
}

mapfile -t GPU_PACKAGES < <(detect_gpu_packages)
ALL_PACKAGES=("${BASE_PACKAGES[@]}" "${GPU_PACKAGES[@]}")

if $DRY_RUN; then
    printf 'Minimal Bootstrap Check\n'
    printf 'Root: %s\n' "$ROOT_DIR"
    printf 'Packages (%d): %s\n' "${#ALL_PACKAGES[@]}" "${ALL_PACKAGES[*]}"
    exec "$ROOT_DIR/deploy.sh" --check
fi

if ! command -v pacman >/dev/null 2>&1; then
    printf 'Error: bootstrap.sh requires an Arch/CachyOS system with pacman.\n' >&2
    exit 1
fi

missing=()
for pkg in "${ALL_PACKAGES[@]}"; do
    pacman -Qq "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done

if ((${#missing[@]} > 0)); then
    sudo pacman -S --needed --noconfirm "${missing[@]}"
fi

for svc in NetworkManager.service bluetooth.service; do
    if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
        sudo systemctl enable --now "$svc" >/dev/null 2>&1 || true
    fi
done

exec "$ROOT_DIR/deploy.sh" "$@"
