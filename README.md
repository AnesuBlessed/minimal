Minimal is a compact Hyprland rice using Foot, Fuzzel, Waybar, Mako, Hyprpaper, hyprlock and hypridle. It targets Hyprland 0.56+, Hyprpaper 0.8+, and Foot 1.28+. Keep the checkout in place after installation: configuration directories are symlinked to it.

The installed session has 10 px app corners, no compositor blur or shadows, and animations capped at 120 ms. The larger launcher uses 11 pt text, 42 columns and eight 30 px rows. It stays horizontally centered and opens about 40 logical pixels below the vertical center; the wrapper adjusts for monitor scale and smaller displays.

The lockscreen uses a cached, pre-blurred version of the selected wallpaper, a native clock, a password field and a battery indicator updated every 30 seconds. The image is prepared once on wallpaper changes, so no continuous blur runs on the GPU. If that cache is missing, locking still works against a dark background. Idle locking occurs after 5 minutes, the display turns off after 5½ minutes, and suspend occurs after 30 minutes. Edit `hypr/hypridle.conf` to change these times.

**Installation when you are ready**

On this machine, the remaining required command at implementation time was `brightnessctl`:

```sh
sudo pacman -S --needed brightnessctl
./deploy.sh --check
./deploy.sh
```

The preflight lists any other missing commands before it changes configuration. Python/Pillow and ImageMagick are used only for short asset-processing jobs; no Python daemon runs. Optional application bindings also use Firefox, Dolphin, pavucontrol, nm-connection-editor, grim, slurp, Satty, playerctl, and blueman-manager (or bluetuith). JetBrainsMono Nerd Font supplies text and symbols.

Log out completely, then select Hyprland at login. A reload alone does not rerun login startup. Deployment does not restart the current desktop. Mako is the notification service for Minimal; the old Dunst directory is left untouched and is not started by this configuration. Hyprpaper is the only wallpaper backend used by Minimal's startup and picker; HyDE/awww is not a prerequisite.

Only `hypr`, `waybar`, `fuzzel`, `foot`, `mako`, `fastfetch`, and the `minimal` root link are managed under `${XDG_CONFIG_HOME:-~/.config}`. Other application configurations are not changed. Every existing managed entry is backed up, including symlink identity. Previously absent entries are recorded too. Backups and transaction recovery files live under that configuration directory's `backups/`. Repeating deployment of the same checkout is a no-op.

**Rollback**

```sh
./restore.sh --check
./restore.sh
```

Restore selects the newest active manifest-based backup and retains all backups afterward. It removes links for entries that were originally absent. If you independently replace a managed link with another directory, restore stops rather than overwrite it. You can select an older manifest explicitly using `./restore.sh --backup /absolute/path/to/backup`. The old `backup_pre_minimal_*` format is not automatically restored because it has no reliable record of originally absent entries.

Both commands accept `--config-dir /absolute/path` for a separate configuration tree. Copy failures are caught before replacement begins; replacement failures trigger rollback. No claim is made that all directory replacements form a single filesystem-atomic operation. Recovery files are retained if a process is forcibly killed or the machine loses power mid-operation.

**Controls**

| Control | Action |
| --- | --- |
| Super+A | Centered application launcher |
| Super+T | Foot terminal |
| Super+F / Super+B | Web Browser (Firefox) |
| Super+M / F11 | Dedicated Fullscreen toggle |
| Super+W | Toggle wallpaper cover-flow carousel |
| Super+Escape / Bar Power | Power menu (Lock, Suspend, Logout, Reboot, Shutdown) |
| Super+L / Power key | Lock session immediately |
| Super+U | USB Removable Drives menu (Browse in Dolphin / Safe Eject) |
| Super+Shift+N | Dismiss current notification |
| Super+Shift+Alt+N | Dismiss all notifications |
| Super+Alt+N | Restore / recall last dismissed notification |
| Super+Shift+D | Toggle Do Not Disturb (silence popups) |
| Volume keys | Adjust volume with replacement progress OSD, capped at 100% |
| Speaker / Mic mute | Toggle mute and display status OSD |
| Brightness keys | Adjust screen backlight, retaining a nonzero minimum |
| Laptop Lid Close | Immediately locks session; logind suspends; wakes screen on open |
| Battery Guard | Warning at $\le$20%, critical alert at $\le$10%, auto-suspend at $\le$5% |

The Mako OSD sits at bottom center, expires after 1.2 seconds and replaces its previous value while keys repeat. It is excluded from notification history. Volume and brightness handlers terminate after each event; there is no polling service. Keyring secrets (`gnome-keyring`), D-Bus portals (`xdg-desktop-portal-hyprland`), USB auto-mounting (`udiskie`), and battery protection start cleanly on session login.

You can try the larger launcher before installation with `./scripts/launcher.sh`. The existing live Fuzzel symlink also picks up its larger geometry on the next launch. The other new startup features become active after deployment and a fresh login.

Wallpapers are read relative to the checkout. Their saved selection goes to `$XDG_STATE_HOME/minimal/current_wallpaper` (with the standard default if unset); thumbnails and lock images go to `$XDG_CACHE_HOME/minimal`. Wallpaper changes also regenerate Fuzzel/Waybar palette values atomically in the checkout, as part of this rice's editable theme. The bundled palette works without an existing cache. Mako and the lock panel use a stable sage accent.

**Validation**

```sh
python3 -m unittest discover -s tests -v
Hyprland --verify-config -c "$PWD/hypr/hyprland.lua"
foot --check-config -c foot/foot.ini
fuzzel --check-config --config fuzzel/fuzzel.ini
qmllint quickshell/hyprquickpaper/shell.qml
```

The integration suite copies the source into temporary directories and mocks hardware/notification commands. It covers deployment recovery, absence and symlinks, repeat installation, palette imports, control failures, OSD values, launcher positioning and cached lock images. It does not lock or suspend your actual session. Full lock/unlock, suspend/resume and physical Fn-key behavior still need a login test on the target hardware.

The configuration follows the installed manuals and the upstream [Hyprlock](https://wiki.hypr.land/Hypr-Ecosystem/hyprlock/), [Hypridle](https://wiki.hypr.land/Hypr-Ecosystem/hypridle/), and [Hyprpaper](https://wiki.hypr.land/Hypr-Ecosystem/hyprpaper/) interfaces. `AUDIT.md` is the earlier audit snapshot, not a description of the subsequently implemented fixes.
