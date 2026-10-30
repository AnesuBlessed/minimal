<div align="center">
<img src="assets/brand/logo-wordmark.png" alt="Minimal" width="560" />

# Minimal

A Hyprland desktop configuration for Arch Linux / CachyOS, with translucent surfaces, wallpaper-derived colors, and Wayland desktop utilities.
</div>

---

## Highlights

- **Modular Lua configuration:** Window rules, keybindings, input, and appearance are split into modules under `hypr/`. Requires a Hyprland build supporting the `hl` Lua API used here; run `./install.sh --doctor` to check your installed build. A minimum supported version has not been established by a version test matrix.
- **Wallpaper themes:** A compiled Rust helper generates shared colors for Waybar, Hyprland borders, Rofi, Mako, Foot, Hyprlock, and wlogout. Running borders, the bar, and managed Mako instances are refreshed; new menus, locks, and terminals use the generated files.
- **Wallpaper selection:** A compiled GTK4/Cairo carousel with a Rofi fallback, plus random selection.
- **Generated Waybar configuration:** Resolves modular JSONC includes and filters selected modules when supported hardware is not detected.
- **Desktop controls:** Audio, brightness, clipboard history, screenshots, and session actions through scripts and keybindings.

---

## Installation & Deployment

Minimal targets **Arch Linux / CachyOS**. The installer links `hypr`, `waybar`, `rofi`, `mako`, `foot`, `wlogout`, and `fastfetch` into `${XDG_CONFIG_HOME:-~/.config}`. Keep the checkout in place: installed configuration and helpers depend on it.

Missing core packages can be installed through pacman after confirmation. Packages unavailable in configured repositories must be supplied separately. Use `--skip-packages` for configuration-only deployment, `--all-packages` to include optional applications, and `--no-tui` to bypass the interactive installer screen. Package definitions live in [native/src/install.rs](native/src/install.rs). The carousel uses native GTK4/Cairo and json-c; it retains its original coverflow layout and controls.

```bash
git clone https://github.com/AnesuBlessed/minimal.git
cd minimal

# Build once (Arch build dependencies: rust, base-devel, pkgconf, gtk4, json-c)
./scripts/build.sh

# Validate dependencies and configuration before touching anything
./install.sh --doctor

# Dry-run preview of symlinks and deployment operations
./install.sh --dry-run

# Perform installation (backs up existing configs automatically)
./install.sh
```

### Deployment Management

| Command | Purpose |
| :--- | :--- |
| `./install.sh --doctor` | Audits package dependencies, syntax, bar includes, and compositor configs |
| `./install.sh --dry-run` | Simulates file operations without modifying the disk |
| `./install.sh --restore` | Restores the latest pre-installation configuration snapshot |
| `./install.sh --restore <path>` | Restores a specific recovery snapshot |
| `./install.sh --uninstall` | Restores the latest recorded configuration snapshot; leaves packages and runtime data installed |

After installation, start a fresh Hyprland session. If `HYPRLAND_CONFIG` selects another configuration, update the session environment to select Minimal; the installer does not install the `scripts/session-env.*` helpers automatically.

Snapshots are stored in `${XDG_STATE_HOME:-~/.local/state}/minimal/backups/` and include an independent standalone `restore.sh`.

---

## Keybindings Reference

### Window & Workspace Navigation

| Shortcut | Action |
| :--- | :--- |
| `Super + Q` | Close active window |
| `Super + Shift + F` | Toggle floating mode |
| `Super + M` / `Super + F11` | Fullscreen active window |
| `Super + [←/→/↑/↓]` | Focus window directionally |
| `Super + Ctrl + [←/→/↑/↓]` | Move window position directionally |
| `Super + Shift + [←/→/↑/↓]` | Resize active window (repeating) |
| `Super + [1-9]` | Switch to workspace 1–9 |
| `Super + Shift + [1-9]` | Move active window to workspace 1–9 |
| `Super + BackSpace` | Toggle "Pocket Dimension" (scratchpad workspace) |
| `Super + Shift + BackSpace`| Send active window into Pocket Dimension |
| `Super + LMB drag` | Move floating window |
| `Super + RMB drag` | Resize floating window |

### Applications & Desktop Tools

| Shortcut | Action |
| :--- | :--- |
| `Super + T` | Open Foot terminal (synced with active theme) |
| `Super + A` | Open application launcher (Rofi) |
| `Super + Tab` | Open active window switcher (Rofi) |
| `Super + C` | Open clipboard history manager (Cliphist) |
| `Super + Shift + C` | Open clipboard history in delete mode (wipe is available inside the menu) |
| `Super + W` | Open wallpaper carousel, with Rofi fallback |
| `Super + Shift + W` | Apply a random wallpaper from collections |
| `Super + Escape` | Open Power & Session Menu (wlogout / Rofi) |
| `Super + L` | Lock screen immediately (Hyprlock) |
| `Super + R` | Reload compositor, then refresh Waybar |

### Audio & System Controls (Hardware & Fallbacks)

Minimal provides dedicated hardware bindings alongside ergonomic keyboard fallbacks:

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `XF86AudioRaiseVolume` / `Super + =` / `Super + F3` | Volume Up | Increases audio volume by 5% with Mako OSD |
| `XF86AudioLowerVolume` / `Super + -` / `Super + F2` | Volume Down | Decreases audio volume by 5% with Mako OSD |
| `XF86AudioMute` / `Super + \` / `Super + F1` | Toggle Mute | Toggles audio sink mute status |
| `XF86AudioMicMute` / `Super + Shift + M` | Toggle Mic | Toggles default microphone mute |
| `XF86MonBrightnessUp` / `Super + Up` / `Super + F7` / `Super + ]` | Brightness Up | Increases screen brightness with Mako OSD |
| `XF86MonBrightnessDown` / `Super + Down` / `Super + F5` / `Super + [` | Brightness Down | Decreases screen brightness with Mako OSD |
| `Super + Space` / `XF86AudioPlay` | Media Play/Pause | Controls active media player via playerctl |
| `XF86AudioNext` / `XF86AudioPrev` | Track Navigation | Next or previous track |

---

## Status Bar (Waybar) & Architecture

Waybar configuration is generated into `${XDG_STATE_HOME:-~/.local/state}/minimal/waybar.json`.

- The initial mode is `custom`, using `waybar/config.jsonc` (requested height: 38px). The other bundled preset, `waybar/layouts/01.jsonc`, requests 10px. Content and CSS can increase the rendered height.
- `Super + R` reloads Hyprland and refreshes the bar, including hardware detection. `./scripts/bar.sh reload` refreshes just the bar.
- `./scripts/bar.sh custom` and `./scripts/bar.sh 01` select a configuration. `next`, `prev`, and `select` remain available. The optional `custom/bar` module is defined but absent from both bundled module lists.
- `./scripts/bar.sh render` writes the resolved configuration and selection state without starting or signaling Waybar.
- Reload normally signals an owned Waybar process with `SIGUSR2`; the helper starts a process if none is found and can replace one using an outdated stylesheet path.

See [Architecture](docs/architecture.md) for paths and runtime behavior, and [Design](docs/design.md) for implemented visual settings.

---

## Wallpaper Picker & Power Menu

- **Wallpaper picker (`Super + W`):** Launches the native GTK4/Cairo coverflow carousel (`build/minimal-carousel`). You can also browse wallpapers via `./scripts/wallpaper.sh --carousel` or `./scripts/wallpaper-carousel.sh`.
- **Collections:** Searches the checkout's `wallpapers/`, `${XDG_DATA_HOME:-~/.local/share}/minimal/wallpapers/`, `~/Documents/Wallpapers/`, and `~/Pictures/Wallpapers/` for PNG, JPEG, and WebP images. Rofi labels include the collection category.
- **Random wallpaper (`Super + Shift + W`):** Applies a random discovered image. Successful committed changes trigger banner and theme generation; a theme refresh failure can leave the new wallpaper applied with the old theme.
- **Power menu (`Super + Escape`):** Opens wlogout with lock, suspend, hibernate, logout, shutdown, and reboot actions. Rofi is used when wlogout is not installed, not when an installed wlogout fails. Both interfaces require a graphical session; suspend and hibernate also depend on system support.

---

## Testing & Quality Assurance

Minimal includes regression and unit tests for deployment, runtime helpers, themes, and wallpaper handling:

```bash
# Run syntax, parsers, and module graph verification
./scripts/check.sh

# Run test suite
./scripts/test.sh
```

The checker runs available external parsers; some checks are skipped when their tools are missing. `./install.sh --doctor` additionally checks dependencies and asks the installed Hyprland to verify its configuration. These checks do not establish visual quality, latency, or working suspend/resume; those require a live desktop test.

---

## License

Source code and configuration use the [MIT License](LICENSE). Bundled artwork is covered separately by [NOTICE.md](NOTICE.md).
