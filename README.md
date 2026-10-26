# Minimal

A blazingly fast, ultra-efficient desktop environment for Hyprland featuring a polished frosted glass aesthetic, rich Waybar layouts, and battle-tested ergonomics—engineered on top of clean, lightweight Wayland primitives without framework bloat.

> **Philosophy:** Pixel-perfect modern aesthetic, zero runtime bloat. No background Python watchers, no image generation pipelines on wallpaper swap, no heavy dependencies. Pure Wayland native tools (`rofi`, `mako`, `hyprpaper`, `waybar`, `wlogout`) engineered for daily reliability and performance.

---

## Architecture & Components

- **Compositor (`hypr/`):** Pure Lua configuration (`hyprland.lua`) for Hyprland 0.56+. Variable Frame Rate (VFR) enabled, smooth 140ms microSnap transitions, 12px rounding, and deep glass borders.
- **Status Bar (`waybar/`):** Full 17-layout suite (`01.jsonc`–`17.jsonc`) with modular CSS pills, hardware indicators, and instant layout switching (`Super + Alt + Up/Down` or `custom/wbar`).
- **Launcher (`rofi/`):** Dual-pane signature card featuring dynamic wallpaper banner, circular mode-switch buttons, and fast application finder (`Super + A`, `Super + Tab`).
- **Clipboard (`scripts/clipboard.sh`, `rofi/`):** Waybar-anchored dropdown with wallpaper banner. Features clean raw-text copy mode (no icons) and dedicated delete mode with `[ ✕ ]` tags and top wipe brush action (`Super + C`, `Super + Shift + C`).
- **Network & Bluetooth:** Battle-tested `network-manager-applet` (`nm-connection-editor`) and `blueman` (`blueman-manager`) with auto-centering modal window rules.
- **Audio & OSD (`scripts/volume.sh`, `mako/`):** WirePlumber / pamixer controls with smooth in-place Mako progress-bar notifications for volume and microphone mute.
- **Power Menu (`wlogout/`, `scripts/powermenu.sh`):** Signature 6-button circular glass layer-shell overlay (`Super + Escape`).
- **Terminal (`foot/`):** Ultra-lean C-native Wayland terminal configured with an obsidian glass palette and Sixel graphics support (`Super + T`).
- **Screenshots & OCR (`scripts/screenshot.sh`):** Grim + Slurp with Satty annotation (`Print`, `Shift + Print`) and instant region OCR directly to clipboard via Tesseract (`Super + Shift + O`).
- **Lockscreen & Idle (`hypr/hyprlock.conf`, `hypr/hypridle.conf`):** Obsidian typography lockscreen with battery indicator, timed screen blanking, and suspend.
- **Wallpaper (`scripts/wallpaper.sh`):** Zero-latency Hyprpaper IPC switcher with interactive Rofi picker (`Super + W`) and randomizer (`Super + Shift + W`).

---

## Keybindings

| Shortcut | Action |
| :--- | :--- |
| `Super + A` | Application Launcher (Rofi Dual-Pane) |
| `Super + Tab` | Window Switcher (Rofi) |
| `Super + T` | Terminal (Foot Client / Server) |
| `Super + C` | Clipboard Manager (Rofi + Cliphist) |
| `Super + Shift + C` | Clipboard Delete Mode |
| `Super + W` | Wallpaper Picker Menu |
| `Super + Shift + W` | Random Wallpaper |
| `Super + Alt + Up / Down` | Next / Previous Waybar Layout |
| `Super + B` | Web Browser (Firefox) |
| `Super + E` | File Manager (Thunar) |
| `Super + Q` | Close Active Window |
| `Super + M` / `Super + F11` | Fullscreen Window |
| `Super + Shift + F` | Toggle Floating |
| `Super + Arrows` | Move Window Focus |
| `Super + Ctrl + Arrows` | Move Window |
| `Super + Shift + Arrows` | Resize Window |
| `Super + 1–9` / `Super + Shift + 1–9` | Switch Workspace / Move Window to Workspace |
| `Super + BackSpace` | Toggle Scratchpad (`pocket`) |
| `Print` | Region Screenshot to Clipboard & Pictures |
| `Shift + Print` | Region Screenshot with Annotation (Satty) |
| `Super + Print` | Fullscreen Screenshot |
| `Super + Shift + O` | Region OCR to Clipboard (Tesseract) |
| `Super + L` | Lock Screen (Hyprlock) |
| `Super + Escape` / `Power` | Power Menu (Wlogout) |
| `XF86MonBrightnessUp / Down` | Adjust Brightness with Mako OSD |
| `XF86AudioRaise / LowerVolume` | Adjust Volume with Mako OSD |
| `XF86AudioMute / MicMute` | Toggle Audio / Microphone Mute |
| `Super + Space` / Media Keys | Music Play / Pause / Next / Prev |
| `Super + R` | Reload Hyprland Configuration & Waybar |

---

## Dependencies

Minimal relies on native, battle-tested Wayland tools without framework bloat:

```bash
# Core Compositor & Environment
sudo pacman -S hyprland waybar rofi-wayland mako foot wlogout hyprpaper hypridle hyprlock

# Media, Hardware & Utilities
sudo pacman -S pamixer wireplumber cliphist grim slurp satty tesseract network-manager-applet blueman brightnessctl

# Fonts & Icons (Recommended)
sudo pacman -S ttf-jetbrains-mono-nerd
```

---

## Directory Layout

```
.
├── fastfetch/             # Sixel greeting configuration and anime character assets
├── foot/                  # Clean obsidian glass terminal configuration
├── hypr/
│   ├── colors.lua         # Central obsidian glass palette
│   ├── hardware.lua       # Wayland toolkit environment variables and VFR
│   ├── hypridle.conf      # Native idle and DPMS timeouts
│   ├── hyprland.lua       # Master Hyprland configuration entrypoint
│   ├── hyprlock.conf      # Centered typography lock screen
│   ├── hyprpaper.conf     # Wallpaper daemon configuration
│   ├── keybinds.lua       # Clean, ergonomic keybindings
│   ├── looknfeel.lua      # Gaps, borders, blur, and microSnap animations
│   ├── monitors.lua       # Auto-detect display configuration
│   ├── paths.lua          # Self-contained path resolution
│   └── rules.lua          # Window and layer rules (floating modals, blur)
├── mako/                  # Notification daemon theme with OSD progress bar
├── rofi/                  # Pure Wayland Rofi themes (dual-pane launcher, clipboard, selector)
│   ├── clipboard.rasi     # Sleek glass clipboard manager theme
│   ├── launcher.rasi      # Signature dual-pane launcher with wallpaper banner
│   ├── selector.rasi      # Minimal centered dmenu selector
│   └── theme.rasi         # Central obsidian glass palette
├── scripts/
│   ├── battery-status.sh  # Minimal sysfs battery reader for lockscreen
│   ├── brightness.sh      # Screen brightness controller with Mako progress bar OSD
│   ├── clipboard.sh       # Rofi clipboard manager with clear brush & delete tags
│   ├── launcher.sh        # Dual-pane application launcher runner
│   ├── lock.sh            # Hyprlock runner with single-instance lock
│   ├── paths.sh           # Portable shell path resolution
│   ├── powermenu.sh       # Wlogout glass power menu runner with Rofi fallback
│   ├── screenshot.sh      # Grim/slurp screenshot and Tesseract OCR
│   ├── session-start.sh   # Session initialization (polkit, cliphist, applets, idle)
│   ├── volume.sh          # Volume & mic OSD controller with Mako progress bar
│   ├── wallpaper.sh       # Lightweight Hyprpaper switcher and Rofi picker
│   └── wbar-switch.sh     # Instant Waybar layout switcher (17 layouts)
├── wallpapers/            # Curated aesthetic wallpapers
├── waybar/                # Full 17-layout suite and modular CSS styling
│   ├── config.jsonc       # Active layout entrypoint (defaults to 01.jsonc)
│   ├── style.css          # Master stylesheet
│   ├── theme.css          # Palette variables
│   ├── defaults.css       # Core pill and leaf styling
│   ├── layouts/           # 17 switchable layout presets (01.jsonc–17.jsonc)
│   ├── modules/           # Modular component definitions
│   └── groups/            # Pill geometry styles
└── wlogout/               # Standalone circular glass power menu and icons
    ├── layout             # 6-action button definitions
    ├── style.css          # Frosted glass styling with hover effects
    └── icons/             # Clean white PNG action icons
```
