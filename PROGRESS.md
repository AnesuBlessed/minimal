# Project Minimal — Implementation Progress

**Project Goal**: Build a lightweight, hardware-universal, high-performance Hyprland rice inspired by the aesthetic screenshots in `customisations i need/`.

---

## Decisions Log
* **Bar Layout**: Floating island capsules (discrete dark rounded pills with spacing).
* **Workspaces**: Numbered buttons (`1 2 [3] 4`) with soft accent highlight on the active workspace.
* **Animation Style**: Ultra-snappy micro-transitions ($\le 100\text{ms}$).
* **Launcher**: `fuzzel` — Native C Wayland launcher styled with dark glass and rounded selection pills.
* **Terminal**: `foot` — Ultra-lean C Wayland terminal with Sixel graphics for the Death Note HUD in Fastfetch.
* **Wallpaper Daemon**: `hyprpaper` — Official lightweight C++ daemon.
* **Target Hardware**: Universal (Intel Haswell iGPU, AMD, and NVIDIA portable fallbacks).

---

## Phase Tracker

| Phase | Milestone | Status | Notes |
| :---: | :--- | :---: | :--- |
| **0** | **Workspace Setup & Architecture** | **Completed** | Organized `~/Projects`, created `minimal/`, established `RULES.md` and `PROGRESS.md`. |
| **1** | **Hyprland Core & Performance Tuning** | **Completed** | Modular Lua configs (`hyprland.lua`, `monitors.lua`, `hardware.lua`, `looknfeel.lua`, `keybinds.lua`, `rules.lua`), verified clean with `hyprland --verify-config`. |
| **2** | **Waybar Floating Island Capsule Bar** | **Completed** | Floating dark rounded pills (`border-radius: 12px`), sage-olive active workspace buttons, WirePlumber event-driven audio, low-overhead hardware stats. |
| **3** | **Fuzzel Translucent Minimalist Launcher**| **Completed** | C-native floating search layout, rounded glass borders (`radius: 12`), pill selection highlight, sage-olive accents. |
| **4** | **Foot Terminal & Sixel Fastfetch HUD** | **Completed** | Native Sixel graphics in Foot, box-drawn specs, Death Note L (Ryuzaki) artwork in Fastfetch, JetBrains Mono font. |
| **5** | **Audio, Brightness, Hyprpaper & Mako** | **Completed** | C-native Mako notification styling, zero-CPU Hyprpaper daemon, sub-millisecond `wallchange.sh` (`Super + W`), WirePlumber/brightnessctl integration. |
| **6** | **Symlink Deployer & Rollback Script** | **Completed** | Non-destructive backup, atomic symlink deployer (`deploy.sh`), and instant rollback (`restore.sh`). |

---

## Recent Updates
* **2026-10-15**: Cleaned and organized [Projects](file:///home/anesu/Projects). Consolidated Java labs into [labs](file:///home/anesu/Projects/labs).
* **2026-10-15**: Analyzed inspiration images in [customisations i need](file:///home/anesu/Projects/minimal/customisations%20i%20need/) and locked in visual design choices.
* **2026-10-15**: Created [RULES.md](file:///home/anesu/Projects/minimal/RULES.md) to enforce zero-bloat daemon rules, VFR discipline, and modular code standards.
* **2026-10-15**: Completed **Phase 1: Hyprland Core & Performance Tuning** using Hyprland's native **Lua (`hyprland.lua`)** engine. Built modular files (`monitors.lua`, `hardware.lua`, `looknfeel.lua`, `keybinds.lua`, `rules.lua`) with custom user keybindings (Foot, Fuzzel, Dolphin, Firefox, Satty, Pocket Dimension). Verified with `hyprland --verify-config` (0 errors, 0 warnings).
* **2026-10-15**: Completed **Phase 2: Waybar Floating Island Capsule Bar**. Crafted [config.jsonc](file:///home/anesu/Projects/minimal/waybar/config.jsonc) and [style.css](file:///home/anesu/Projects/minimal/waybar/style.css).
* **2026-10-15**: Refined Waybar based on live user feedback & screenshot comparison:
  - Replaced colored emoji coffee with HyDE's native Nerd Font glyph (`󰛊` inactive, `󰅶` active).
  - Split left side into two discrete pills: Hardware stats `[ 󰍛 %  󰾆 G ]` and Caffeine/Clock `[ 󰛊 HH:MM:SS ]`.
  - Grouped controls and connectivity into discrete pills matching HyDE's exact arrangement.
  - Generously spaced out internal module padding (`0 6px`) and capsule margins (`4px 5px`).
  - Added dedicated Microphone input control (`wireplumber#source`) with volume scroll and click-to-mute.
  - Full AC/BAT0 power detection (`󱐋 100%`).
  - Established central dynamic palette architecture ([colors.css](file:///home/anesu/Projects/minimal/colors.css) & [colors.lua](file:///home/anesu/Projects/minimal/hypr/colors.lua)).
* **2026-10-15**: Refined **Fuzzel Launcher** based on user feedback & reference screenshots:
  - Scaled down font from `size=11` to `size=9.5` (`line-height=22`) for sharp, compact typography on 1366x768 display.
  - Adjusted geometry to `width=32` characters and `lines=7` matching the compact proportions in `pasted file2 (1).png`.
  - Added `selection-radius = 8` and `radius = 14` for soft, rounded pill highlights.
  - Resolved missing app icons by switching `icon-theme` to `Tela-circle-dracula` (6,591 icons, replacing breeze-dark's 470) with fallbacks to `hicolor` and `breeze`.
  - Added smart shell fallback for `terminal` execution (`footclient || foot || kitty`).
  - Fixed Waybar CSS group selectors (`#hardware`, `#time-caffeine`, `#controls`, `#connectivity`) so all floating island pills render as separate discrete capsules with 10.5px font size.
* **2026-10-15**: **Cleaned Failed GTK Attempt & Adopted Quickshell Carousel**:
  - Completely cleaned up the failed GTK prototype (`wallpaper_picker.py`, temporary caches, and window rules).
  - Adopted standalone **Quickshell Cover-Flow Carousel** ([hyprquickpaper](file:///home/anesu/Projects/minimal/quickshell/hyprquickpaper/)) powered by `extra/quickshell` (1.6 MB).
  - Configured 108 high-resolution wallpapers in [wallpapers](file:///home/anesu/Projects/minimal/wallpapers/) with automated thumbnail cache generation.
  - Features true 3D-skewed cards (`skewFactor: -0.2`), dock-style magnification where the center card expands prominently, edge-to-edge cropped artwork (`fillMode: PreserveAspectCrop`), and sage-olive highlight border (`#b8c470`).
  - Integrated with `awww` transitions and wired into [wallchange.sh](file:///home/anesu/Projects/minimal/scripts/wallchange.sh) on **`Super + W`**. Pure on-demand utility (terminates immediately on selection with 0 MB background RAM).
* **2026-10-15**: **Waybar Clean Frosted Glass & Halo Removal**:
  - Eliminated the white border/glow outline around Waybar floating capsules by overriding border and box-shadow styles in [user-style.css](file:///home/anesu/.config/waybar/user-style.css) and [style.css](file:///home/anesu/Projects/minimal/waybar/style.css).
  - Configured translucent dark glass (`rgba(20, 20, 26, 0.65)`) with Hyprland dual-pass lightweight blur (`size = 5, passes = 2`).
  - Active workspace button styled with crisp, high-contrast micro-radius pill (`#d9d9d9` on `#1a1a20`).
* **2026-10-15**: **Sleek Minimalist Notification Stack (Dunst & Mako)**:
  - Removed bloated 128px default HyDE hyprdots fallback icon from notification templates.
  - Sized down icons to sleek 38px with 10px internal padding, 1px subtle frame, and 8px rounded corners.
  - Fixed notification font to `JetBrainsMono Nerd Font 10` with bold summary title and clean body formatting.
  - Added notification layer blur rules in [rules.lua](file:///home/anesu/Projects/minimal/hypr/rules.lua).
  - Version-controlled in [minimal/dunst/dunst.conf](file:///home/anesu/Projects/minimal/dunst/dunst.conf) and linked in [deploy.sh](file:///home/anesu/Projects/minimal/deploy.sh).
* **2026-10-15**: **Fastfetch Anime Character Library**:
  - Extracted transparent anime character cutouts into [assets](file:///home/anesu/Projects/minimal/fastfetch/assets/) (Death Note Ryuzaki, Chainsaw Man Pochita, Akame ga Kill, Toradora Taiga, Code Geass, Anime Girl).
  - Built [set_fastfetch_char.sh](file:///home/anesu/Projects/minimal/scripts/set_fastfetch_char.sh) for instant switching or randomizing characters on terminal spawn.
* **2026-10-15**: **Dynamic Wallpaper Adaptation & High-Contrast Waybar Indicators**:
  - Unlocked dynamic wallbash extraction across the system by bypassing hardcoded theme overrides.
  - Linked [colors.css](file:///home/anesu/Projects/minimal/colors.css) to live Wallbash cache, allowing Waybar glass to tint dynamically to current wallpaper colors.
  - Ensured workspace dots, battery, WiFi, audio, and hardware metrics remain high-contrast pure white (`#ffffff` and `rgba(255,255,255,0.75)`) so status text never gets washed out by background hues.
  - Built [update_fuzzel_colors.py](file:///home/anesu/Projects/minimal/scripts/update_fuzzel_colors.py) to dynamically theme Fuzzel's launcher palette on wallpaper change while preserving PNG icons via `hicolor`.
* **2026-10-15**: **Wallpaper Carousel Scroll Calibration & Binding Loop Elimination**:
  - Eliminated QML binding loop (`scaleFactor` fighting `delegateItem.width`) by locking slot widths to `baseWidth` and scaling visual content with GPU transforms.
  - Replaced runaway `SmoothedAnimation { anim.v = 5000 }` with smooth cubic-eased `NumberAnimation` (180ms).
  - Added threshold wheel accumulator and rate-limiting cooldown to prevent trackpad flicks and sensitive wheels from jumping uncontrollably.
  - Removed hover index switching loop so moving the mouse never disrupts scrolling momentum.

