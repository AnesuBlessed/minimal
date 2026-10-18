# Minimal — Future Roadmap

> **Core Rule:** Every future addition must preserve Minimal's zero-idle-daemon architecture (0 MB idle RAM when closed, sub-0.4% idle CPU, hardware-agnostic, and transactionally safe).

---

## 1. On-Demand Quickshell Control Center (`Super + S`)
- **Goal:** Replace external GTK settings utilities (`pavucontrol`, `blueman-manager`, `nm-connection-editor`) with a single unified, bottom-anchored Quickshell popup (`quickshell/control-center/shell.qml`).
- **Features:**
  - **Audio:** PipeWire output & microphone sliders + sink/source device switcher via `wpctl`.
  - **Display & Idle:** Brightness slider (`brightnessctl`), Night Light toggle (`hyprsunset`), and Caffeine toggle (`scripts/caffeine.sh`).
  - **Wi-Fi & Bluetooth:** Fast network switcher (`nmcli` JSON/tabular output) and Bluetooth power/device toggle (`bluetoothctl`).
- **Idle Cost:** **0 MB RAM** (process exits immediately when popup closes).

---

## 2. Interactive Monitor & Refresh-Rate Switcher (`Super + P`)
- **Goal:** Seamless multi-monitor and high-refresh-rate management for future desktop/external-display setups (`quickshell/monitors/shell.qml`).
- **Features:**
  - Reads live connected outputs and modes from `hyprctl monitors -j`.
  - One-click presets: **Extend Right**, **Extend Left**, **Mirror Display**, **External Only**, **Internal Only**.
  - Per-display resolution, refresh rate (`60Hz` / `144Hz` / `240Hz`), VRR, and fractional scale (`1.0` / `1.25` / `1.5` / `2.0`) selector.
  - Persists monitor profiles by EDID/model name into `~/.local/state/minimal/monitors.json` so `hypr/monitors.lua` automatically applies your saved layout whenever a display is plugged in.

---

## 3. Screen Recording & Instant OCR (`scripts/screenshot.sh`)
- **Goal:** Extend `scripts/screenshot.sh` and `Super + /` with hardware-accelerated screen recording and region OCR.
- **Features:**
  - **Region / Full Screen Recording (`Super + Shift + R`):** Uses `wl-screenrec` or `wf-recorder` with VA-API hardware encoding and `slurp` region selection; displays a minimal recording badge in Waybar only while active.
  - **Instant Region OCR (`Super + Shift + O`):** Captures a screen region via `slurp` + `grim`, extracts text locally with `tesseract`, and copies it straight into `wl-copy`.

---

## 4. GTK-3 / GTK-4 & File Manager Accent Synchronization (`scripts/sync-theme.py`)
- **Goal:** Make third-party GTK/Qt windows match the active wallpaper palette automatically.
- **Features:**
  - Extend `scripts/sync-theme.py` and `scripts/wallpaper.sh` transaction rollback to generate `~/.config/gtk-3.0/gtk.css` and `~/.config/gtk-4.0/gtk.css` accent variables derived from `theme.json`.
  - Keeps Thunar/Dolphin and system dialogs visually consistent with Waybar, Foot, and Quickshell popups.

---

## 5. Bare-Metal Arch / CachyOS Bootstrap (`bootstrap.sh`)
- **Goal:** Turn a fresh Arch/CachyOS installation on a new PC into your complete working environment in one command.
- **Features:**
  - Installs base packages, PipeWire audio stack, GPU VA-API drivers, and fonts.
  - Configures Fish shell + Fastfetch greeting, display manager (`greetd` / `ly`), and power rules.
  - Runs `./deploy.sh` transactionally so moving to a new machine takes under 2 minutes.
