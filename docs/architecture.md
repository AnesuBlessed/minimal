# Minimal Architecture

## Native helpers

Minimal's desktop helpers are compiled; no Python interpreter or Python packages are required to build, run, install, or test this checkout.

- [native/src](../native/src/main.rs) builds `build/minimal`, a Rust executable with subcommands for bar generation, clipboard actions, wallpaper discovery/application, image caches, palettes, terminal startup, installation, and configuration checks.
- [native/carousel.c](../native/carousel.c) builds `build/minimal-carousel`, using GTK4, Cairo, GLib, and json-c. It preserves the existing fullscreen coverflow, landscape preview, metadata, keyboard navigation, scrolling, category selection, and card clicking.
- Shell entry points under `scripts/` keep the same public commands and call `scripts/native.sh`. The build is explicit: `./scripts/build.sh`. Runtime commands never invoke a compiler.

The build requires Rust/Cargo, a C compiler, pkg-config, GTK4 development files, and json-c development files. Cargo dependencies are locked in `native/Cargo.lock`. On Arch, the build packages are `rust`, `base-devel`, `pkgconf`, `gtk4`, and `json-c`. A first build downloads the locked Rust dependencies. Runtime image decoding and palette generation use the native Rust image library, without an ImageMagick subprocess.

## Carousel behavior

The native picker carries over the original 156×410 center-card geometry, arc spacing, depth dimming, generated accent, 340×192 preview, labels, and per-frame 24% easing. Arrow keys and h/j/k/l browse, Page Up/Down move five entries, Home/End jump, Tab cycles categories, Enter/Space apply, and Escape/q close. Mouse wheel and card/preview clicks retain their actions.

Two background workers load or generate thumbnails. Disk cache keys include the full source path, modification time, dimensions, and image kind. The in-memory cache is bounded to 48 entries and pending thumbnail work to 36 jobs. Disk cache reads also run off the GTK drawing thread. Image interpolation can differ slightly from the former implementation.

Applying runs in a subprocess so GTK keeps drawing. The picker closes on success; on failure it shows a retry message instead of silently closing. Navigation and closing are held while application is in progress. The existing Rofi fallback remains available if the carousel cannot launch; `wallpaper.sh --rofi` selects it explicitly.

## Installation and recovery

[native/src/install.rs](../native/src/install.rs) links seven directories into the XDG configuration directory: `hypr`, `waybar`, `rofi`, `mako`, `foot`, `wlogout`, and `fastfetch`. Originals are copied before replacement. A staging directory retains exact previous entries during deployment so a failed deployment can roll them back. Reinstalling an already linked checkout preserves the recovery point; partial relinks carry forward the user's original configuration.

Recovery snapshots contain `manifest.json`, original files, a copy of the native helper, and a standalone `restore.sh`. New snapshots need no interpreter or checkout to restore. Older snapshots remain untouched and use the recovery tools they originally recorded. Restore/uninstall restores configuration; it does not remove packages or generated data.

The installer retains a terminal review screen with Enter to proceed and Escape/q to cancel; `--no-tui` bypasses it. `--dry-run` previews deployment, `--skip-packages` skips package management, and `--all-packages` includes optional tools. The installer does not deploy `scripts/session-env.*`; these remain session-configuration helpers.

Installed configuration and helper launchers depend on the checkout and its `build/` directory remaining available.

## Hyprland and Waybar

[hypr/hyprland.lua](../hypr/hyprland.lua) uses the compositor's `hl` API and reloads its component modules after clearing their Lua cache entries. Modules cover paths, monitors, hardware, appearance, rules, colors, and shortcuts. Monitor defaults use preferred mode, automatic placement, and scale 1.0, with optional state-directory `monitors.lua` overrides. The `hyprland.start` event runs `session-start.sh`.

`Super + R` reloads Hyprland and then refreshes Waybar. There is no numeric compatibility matrix; `./install.sh --doctor` checks the installed compositor's configuration parser.

The native bar helper resolves JSONC includes and validates module/group references. Initial mode is `custom` (`waybar/config.jsonc`, requested height 38px); preset `01` requests 10px. CSS/content can increase actual height. `next`, `prev`, and `select` remain available. The optional `custom/bar` module is defined but absent from both bundled lists.

Hardware filtering detects selected hwmon sensors, backlights, and `BAT*` power supplies. Missing detections remove corresponding module references. `bar.lock` serializes generation. Reload signals an owned Waybar process with `SIGUSR2`; it starts one when absent or replaces one using an outdated stylesheet path. `render` writes configuration and selection without launching or signaling Waybar.

## Wallpapers and themes

[native/src/wallpaper.rs](../native/src/wallpaper.rs) searches checkout `wallpapers/`, XDG data `minimal/wallpapers/`, `~/Documents/Wallpapers/`, and `~/Pictures/Wallpapers/`. PNG, JPEG, and WebP are supported. Resolved paths are deduplicated; categories use the first relative directory.

Application validates the image and takes `wallpaper.lock`. It tries a running awww daemon, a running swww daemon, then Hyprpaper. Hyprpaper queries monitor names and considers a change successful if at least one target accepts it. Rejection preserves selection state. A successful change updates `current_wallpaper` and `wallpaper.set`, refreshes banners and themes, and notifies Waybar. Theme failure does not roll back an applied wallpaper.

[native/src/theme.rs](../native/src/theme.rs) decodes images with orientation correction, samples a reduced image into color bins, scores prevalence/saturation/brightness, and derives colors with fixed lightness targets. The result is not a measured contrast guarantee and can differ from the old quantizer. It generates `palette.json`, `colors.lua`, `borders.lua`, `waybar.css`, `rofi.rasi`, `mako.conf`, `hyprlock.conf`, `foot.ini`, and `wlogout.css`.

Files are individually replaced atomically, not as a single theme transaction. Refresh attempts border updates through `hyprctl repl`, Waybar reload, managed Mako refresh, and a GSettings accent update. New menus, locks, and terminals read generated colors; existing terminals are not recolored. Some external refresh failures are best-effort.

## Storage

| Location | Contents |
| --- | --- |
| Checkout `build/` | Compiled helpers, ignored by Git |
| Checkout `native/target/` | Cargo build artifacts, ignored by Git |
| `${XDG_CONFIG_HOME:-~/.config}` | Installed configuration links |
| `${XDG_STATE_HOME:-~/.local/state}/minimal` | Recovery snapshots, wallpaper/layout selection, generated bar config/CSS/log/PID and themes |
| `${XDG_CACHE_HOME:-~/.cache}/minimal` | Banners and carousel thumbnails |
| `${XDG_DATA_HOME:-~/.local/share}/minimal/wallpapers` | Optional wallpaper collection |
| `${XDG_RUNTIME_DIR}/minimal` | Picker/session locks; fallback is XDG cache `minimal/runtime/minimal` |

The power menu uses temporary layout/CSS files and removes them on exit. It uses wlogout if installed and otherwise Rofi. Both require a graphical session.

## Verification

`./scripts/test.sh` runs Rust regression tests, shell/configuration checks, and GTK carousel control tests on an isolated Broadway display when its tools are available. The GTK tests do not apply wallpapers. `./scripts/check.sh` validates shell syntax, available Lua/Rofi/Foot parsers, and bar include/module resolution. `./install.sh --doctor` adds dependency and compositor checks.

`MINIMAL_ROOT="$PWD" build/minimal-carousel --snapshot /tmp/picker.png` renders the picker offscreen without changing the wallpaper. Rendering differences, hardware behavior, and suspend/resume still need appropriate desktop tests. Performance measurements of one helper do not establish performance for the entire desktop.
