# Minimal

A lightweight, zero-bloat Hyprland desktop environment for Arch Linux.

## How It Works

- **Native Hyprland Lua (`hypr/`):** Configured directly in Lua (`hyprland.lua`) with modular files for hardware, monitors, keybindings, window rules, and appearance.
- **Hardware-Aware Startup (`scripts/hardware-detect.sh`):** Detects your GPU (Intel, AMD, NVIDIA, hybrid, or VM) at login and configures VA-API/VDPAU drivers, VFR, and rendering flags automatically.
- **Scoped Session Lifecycle (`scripts/session-start.sh`):** Core services (Waybar, Hyprpaper, Mako, Hypridle, Foot server, native C automounter, and session guard) run as isolated `systemd --user` units tied to the active display.
- **On-Demand Quickshell Popups (`quickshell/`):** Application launcher, clipboard manager, wallpaper picker, keybind cheat-sheet, Dynamic Notch (media + 3-day weather), unified Control Center (Wi-Fi, Bluetooth, Audio, Display), and Monitor Switcher launch on demand and exit on close (0 MB idle RAM).
- **Dynamic Palette & Live Keybinds:** Changing wallpapers (`Super + W` or `Super + Shift + W`) extracts a new accent color and updates Waybar, Foot, Fuzzel, Mako, Wlogout, Hyprland, Hyprlock, Quickshell, and GTK-3/4/libadwaita (`assets/gtk-accent.css`) transactionally. Editing `hypr/keybinds.lua` automatically updates the `Super + /` cheat-sheet and Waybar tooltip.

## Install

Keep this repository where you clone it (deployment links `~/.config` entries directly to this checkout):

```sh
git clone https://github.com/AnesuBlessed/minimal.git ~/Projects/minimal
cd ~/Projects/minimal
./deploy.sh --check
./deploy.sh
```

For a bare-metal Arch / CachyOS installation (installs GPU VA-API/Vulkan drivers, PipeWire, fonts, services, and runs `deploy.sh`):

```sh
./bootstrap.sh
```

`deploy.sh` checks required packages, installs any missing dependencies via `pacman`, backs up your existing configs under `~/.config/backups/`, links the managed components (`hypr`, `waybar`, `wlogout`, `fuzzel`, `foot`, `mako`, `fastfetch`, `minimal`), and registers the **Minimal (Hyprland)** display-manager session. Log out and select **Minimal (Hyprland)** at login.

## Uninstall / Restore

To remove Minimal's symlinks and restore your previous configuration from the automatic backup:

```sh
cd ~/Projects/minimal
./restore.sh --check
./restore.sh
```

If you want to delete the checkout entirely after restoring:

```sh
rm -rf ~/Projects/minimal
```

## Keybindings

| Shortcut | Action |
| --- | --- |
| `Super + A` | Application Launcher |
| `Super + S` | Unified Control Center (Quick Toggles, Wi-Fi, Bluetooth, Audio, Display) |
| `Super + I` | Dynamic Notch Popup (MPRIS Media Player & 3-Day Weather Forecast) |
| `Super + P` | Display & Monitor Switcher (Multi-Monitor Presets, Refresh Rate, Scale, VRR) |
| `Super + T` | Terminal (Foot) |
| `Super + B` / `Super + F` | Web Browser |
| `Super + E` | File Manager |
| `Super + C` | Clipboard History |
| `Super + W` / `Super + Shift + W` | Wallpaper Picker / Random Wallpaper |
| `Super + U` | USB Drive Menu |
| `Super + /` | Interactive Keybind Cheat-Sheet |
| `Super + Q` | Close Active Window |
| `Super + M` / `Super + F11` | Fullscreen Window |
| `Super + Shift + F` | Toggle Floating |
| `Super + Arrows` | Move Window Focus |
| `Super + Ctrl + Arrows` | Move Window |
| `Super + Shift + Arrows` | Resize Window |
| `Super + 1–9` / `Super + Shift + 1–9` | Switch Workspace / Move Window to Workspace |
| `Super + BackSpace` | Toggle Scratchpad (`pocket`) |
| `Super + N` / `Super + Shift + B` / `Super + V` | Control Center: Wi-Fi / Bluetooth / Audio Tabs |
| `Print` / `Shift + Print` / `Super + Print` | Region / Annotated / Full Screenshot |
| `Super + Shift + R` | Toggle Region MP4 Screen Recording |
| `Super + Shift + O` | Instant Region OCR to Clipboard |
| `Super + L` / `Super + Escape` | Lock Screen / Power Menu |
| `Super + R` | Reload Hyprland & Waybar |

## Layout

- `hypr/` — Hyprland Lua configuration, Hyprlock, and Hypridle
- `waybar/` — Modular status bar configuration and styles (including reactive center Dynamic Notch)
- `quickshell/` — Launcher, Clipboard, Wallpaper Picker, Keybinds, Control Center, Dynamic Notch, Monitors, and shared palette
- `foot/`, `fuzzel/`, `mako/`, `wlogout/`, `fastfetch/` — Component configs
- `scripts/` — Session management, hardware detection, theme sync, and native C helpers
- `theme.json` — Single source of truth for colors, radii, opacity, and typography
