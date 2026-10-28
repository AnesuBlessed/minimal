<div align="center">
<img src="assets/brand/logo-wordmark.png" alt="Minimal" width="560" />

# Minimal

A self-contained Hyprland desktop with dark blue glass, lavender accents, and native Wayland tools.
</div>

Minimal bundles its bar styles, modules, launcher, notifications, terminal,
lockscreen, and power menu. Python's standard library powers installation,
validation, and short-lived configuration helpers; there are no Python watchers.

## Install

Target: Arch Linux / CachyOS, Hyprland's Lua configuration API (0.56.x),
Hyprpaper 0.8.x, Rofi 2.x, and Waybar 0.15.x. Local validation used Hyprland
0.56.2, Hyprpaper 0.8.4, Rofi 2.0.0, Waybar 0.15.0, and Foot 1.28.0.
Future versions still need validation. Python 3 is required to run the installer.

```bash
git clone https://github.com/AnesuBlessed/minimal.git
cd minimal
./install.sh --dry-run
./install.sh
```

The interactive review screen and CLI use the same backend. Missing packages
are listed before installation; package errors stop deployment. The package
manifest lives in `scripts/install.py`. Package availability can differ by
repository; supply unavailable packages yourself, then use `--skip-packages`
for configuration-only deployment.

Seven config directories are linked to this checkout: `hypr`, `waybar`, `rofi`,
`mako`, `foot`, `wlogout`, and `fastfetch`. Keep the checkout at the same path
while using it. Existing directories, files, and symlinks are backed up before
replacement. Interrupted or failed changes can be recovered from the snapshot.
Deployment is recoverable, not a single atomic filesystem transaction.

Start a fresh Hyprland session after installation. Installing does not replace
running daemons or change the current session. In a Minimal session, `Super + R`
reloads compositor settings and the managed bar.

```bash
./install.sh --no-tui --dry-run  # Read-only preview, including custom XDG paths
./install.sh --doctor           # Config parsers, module graph, dependency audit
./install.sh --restore --dry-run
./install.sh --restore          # Latest recorded recovery point
./install.sh --restore /absolute/path/to/backup
./install.sh --uninstall        # Alias for restoring the latest recovery point
```

Snapshots live in `${XDG_STATE_HOME:-~/.local/state}/minimal/backups/` and include
an independent `restore.sh`. Recovery restores previous contents and removes
components that did not exist before installation. Reinstalling the same fully
linked checkout preserves the recovery point. Restore replaces the seven
managed config paths, including changes made there since the snapshot; copy
anything you want to keep first. Package installation is not reversed.

## Bar and theme

The checked-in `waybar/config.jsonc` preserves the current customized layout.
All 17 existing presets retain their original group arrangements, geometry,
fonts, and pill/leaf styling. Broken module references are repaired in place.
Use the bar's layout button (left: next, right: previous, middle: picker),
`Super + Alt + Up/Down`, or:

```bash
./scripts/bar.sh 01
./scripts/bar.sh custom   # Return to waybar/config.jsonc
```

The selected existing preset, generated config, PID, and diagnostic log live under the Minimal
state directory. Switching never rewrites the repository. Only the bar started
by Minimal is signaled. Logs are in `minimal/waybar.log` under that state directory.

Theme files are owned by Minimal: `waybar/theme.css`, `rofi/theme.rasi`,
`hypr/colors.lua`, `hypr/hyprlock.conf`, `mako/config`, `foot/foot.ini`, and
`wlogout/style.css`. Put personal bar CSS overrides in `waybar/user-style.css`.
See [the design guide](docs/design.md) for the shared visual conventions.

Idle inhibition and media metadata use native Waybar modules. Unimplemented
GPU, weather, theme-switching, workflow, game-mode, and night-light buttons have
been removed from the shipped layouts. Hardware indicators are omitted when
the corresponding battery, backlight, or CPU sensor is absent. Optional modules
such as MPD, power profiles, display settings (`nwg-displays`), and Cava require
the corresponding services or Waybar build features when explicitly enabled.

## Everyday tools

The launcher has a visible search field and application/window/command modes.
Clipboard history supports copy, delete, and confirmed wipe. Wallpaper selection
uses bundled images and `~/Pictures/Wallpapers`; state is saved only after
Hyprpaper accepts the change. Commas in wallpaper paths are rejected because
the IPC request uses comma separators.

The power menu uses a three-column, two-row card grid with keyboard focus.
Suspend and hibernate depend on the machine's system configuration. The
lockscreen uses Hyprlock authentication and Hypridle locks before sleep.

To enable the optional Fish greeting, source `fastfetch/greeting.fish` from your
Fish configuration. `scripts/set_fastfetch_char.sh list` lists available art;
selecting a character stores the choice in state rather than modifying assets.

## Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Super + A` | Application Launcher (Rofi) |
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
| `Super + Shift + BackSpace` | Move Window to Scratchpad (`pocket`) |
| `Super + LMB (drag)` | Move Window |
| `Super + RMB (drag)` | Resize Window |
| `Super + Scroll Up / Down` | Switch to Prev / Next Workspace |
| `Print` | Region Screenshot to Clipboard & Pictures |
| `Shift + Print` | Region Screenshot with Annotation (Satty) |
| `Super + Print` | Fullscreen Screenshot |
| `Super + Shift + O` | Region OCR to Clipboard (Tesseract) |
| `Super + L` | Lock Screen (Hyprlock) |
| `Super + Escape` / `Power` | Power Menu (Wlogout) |
| `Laptop Lid Switch` | Lock Screen on Close / Display On on Open |
| `XF86MonBrightnessUp / Down` | Adjust Brightness with Mako OSD |
| `XF86AudioRaise / LowerVolume` | Adjust Volume with Mako OSD |
| `XF86AudioMute / MicMute` | Toggle Audio / Microphone Mute |
| `Super + Space` / Media Keys | Music Play / Pause / Next / Prev |
| `Super + R` | Reload Hyprland Configuration & Waybar |

## Development and validation

```bash
python3 scripts/check.py
python3 -m unittest discover -s tests -v
./install.sh --doctor
```

CI checks shell/Python/Lua syntax, GTK CSS, module references, and regression
tests for deployment and runtime state. Local checks also use Rofi and Foot
parsers when installed. Doctor returns a nonzero status for errors and missing
dependencies; parser success does not certify hardware behavior.

There is no verified resting-memory claim. Use real measurements on your own
hardware rather than treating a static configuration as a performance benchmark.

## License and assets

Source code is MIT licensed; see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
Bundled artwork is not relicensed by the code license. Artwork provenance and
redistribution permissions remain to be established before an artwork release.
