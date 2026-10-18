# Whole-project audit — 2026-10-18

Current working tree, including uncommitted changes. This supersedes the earlier visual-only `AUDIT.md` as the current assessment; it does not attribute defects to particular authors. No implementation files were changed during this audit.

## Scope and evidence

| Area | Review performed |
| --- | --- |
| Install / restore | Dependency checks, backup manifests, rollback, session registration, bootstrap |
| Session / hardware | Startup ordering, environment, service ownership, native helpers, hardware selection |
| Safety / power | Locking, idle settings, battery checks, caffeine, power actions |
| Desktop tools | Screenshots, recording, OCR, notifications, media controls, USB, launcher, keybinds |
| Wallpaper / theme | Image/video application, persistence, rollback, downloads, generated themes |
| Clipboard | Decode limits, cache lifecycle, search, mutation helper and Settings integration |
| Settings / Bluetooth | All six page implementations, control wrappers, transfer agent/sender/UI |
| UI / configuration | Quickshell entry points, Waybar active layout and module references, native styles |
| Tests / docs | Existing suite, syntax checks, isolated reproductions, README and roadmap claims |

Validation: 101 existing tests passed in the immediately preceding audit of this same working tree. All 47 shell, 14 Python, and 9 Lua files passed syntax checks. Both C helpers passed compiler syntax checks with `-Wall -Wextra -Werror`. QML lint reported zero `Error:` diagnostics; warnings were retained in `/tmp/minimal-project-qmllint.log`. This does not establish that every UI binding or interaction works.

Live visual checks in this audit sequence covered Waybar, Sound, and Maintenance. The preceding visual pass covered all Settings pages, but that is not a substitute for rechecking every newly changed page. No real pairing, file transfer, destructive maintenance, display-mode change, suspend, logout, or deployment was performed. Fresh-machine installation, multi-GPU/multi-monitor hardware, and simultaneous real sessions remain unverified.

## High-priority findings

### H1. Lock isolation fails across displays — reproduced

`scripts/lock.sh:9`, `scripts/paths.sh:7`

The lock guard is `$MINIMAL_RUNTIME/lock.lock`, and the runtime directory is shared by all compositor instances for the same user. A locker on display A holds the guard, causing display B's lock request to exit 0 without launching its own locker. Isolated reproduction used two compositor signatures and two Wayland display names: the second request returned success and only one mocked locker launched.

Use a compositor-specific runtime namespace for lock ownership. Audit popup, recording, and other PID files under that same shared directory too. Shared wallpaper preferences can remain user-wide; process ownership cannot.

### H2. Bluetooth automatically approves pairing and service authorization — source-confirmed

`scripts/bluetooth-agent.py:69`, `scripts/bluetooth-agent.py:204`, `scripts/session-start.sh:55`

The default agent accepts confirmation, authorization, and service requests without asking the user. Startup sets unlimited discoverability and pairability. Incoming-file consent does not provide consent for pairing itself. Legacy PIN/passkey methods also return fixed zero values.

Require explicit pairing consent, show passkeys where applicable, and make discovery an explicit bounded operation. Preserve the user's adapter identity and visibility choices rather than resetting the alias to `minimal` each session.

### H3. Transfer state is not associated with a transfer — reproduced

`scripts/bluetooth-agent.py:214`, `scripts/bluetooth-send.py:215`

Both directions write `bt-transfer.json` and its fixed `.tmp` sibling and consume shared action/cancel files. The agent listens to all transfer property events without checking the transfer path. An isolated callback reproduction showed an unrelated transfer completion marking an outgoing transfer complete. Concurrent writers can also interfere with temporary-file replacement.

Introduce a transfer identifier, ownership filtering, and per-transfer action/state files or a single serialized transfer manager. Do not derive the active operation from whichever file was written last.

### H4. Cancellation can leave the actual transfer running — API/source-confirmed

`scripts/bluetooth-send.py:267`

The sender calls `Cancel` on the ObjectPush interface rather than the returned Transfer interface. The caught exception skips the subsequent session removal, yet the UI is updated to cancelled. Both incoming and outgoing cancellation are checked only when a property event arrives, so a stalled transfer need not observe cancellation.

Cancel the specific transfer independently of progress events and update the UI only after resolving the result. BlueZ defines cancellation on `org.bluez.obex.Transfer1`: <https://bluez.readthedocs.io/en/latest/obex-api/#transfer-hierarchy>.

### H5. Idle settings are saved but the owned service uses another file — reproduced

`scripts/idle-config.sh:64`, `scripts/session-start.sh:54`, `hypr/hypridle.conf`

Settings generates `$MINIMAL_STATE/hypridle.conf`, then restarts the service. That service was created with `$MINIMAL_ROOT/hypr/hypridle.conf`, so it restarts using unchanged defaults. Reproduced with an isolated 600-second setting: the JSON and generated file changed, but only a restart of the statically configured unit occurred. Status defaults also say blank=300 while the shipped screen-blank timeout is 330.

Use one effective configuration at startup and reload. Surface restart failure rather than reporting only saved preference values.

## Functional and reliability findings

### M1. Idle fallback can terminate another session's daemon

`scripts/idle-config.sh:73`

When the owned unit is absent, the fallback uses unscoped `pgrep`/`pkill -x hypridle`. This breaks the otherwise deliberate service-ownership design. Restart only a positively identified owned process or create the intended owned unit.

### M2. Recording announces success before knowing the recorder started — reproduced

`scripts/screenshot.sh:47`

A mocked recorder that immediately exited 1 still produced “Recording started” and left `recording.pid`. Stopping also announces “saved” immediately after signalling, without waiting for finalization. Starts are not serialized, so rapid invocations can create multiple writers. The notification refers to a removed Notch; no current Waybar recording module exists.

Own the recording lifecycle, detect startup failure, serialize toggles, wait for completion, and expose an actual recording indicator. Test the recorder path itself: the existing recording/OCR test exercises OCR only.

### M3. Bluetooth timeout exits successfully without cleanup

`scripts/bluetooth-send.py:324`

The five-minute timer quits the loop but leaves the default success exit code, session, and “transferring” state. Use a dedicated timeout handler that cancels/removes the session, records a terminal failure, and exits nonzero.

### M4. Incoming file approval blocks the agent's event loop

`scripts/bluetooth-agent.py:171`

The D-Bus authorization callback sleeps and polls for up to 35 seconds. During that wait the same GLib loop cannot normally dispatch other agent callbacks and transfer events. Use asynchronous authorization and a timer-driven deadline. Startup registration exceptions are also swallowed, leaving a process that may run without a registered agent; expose registration failure and handle service restarts.

### M5. Wi-Fi Disconnect passes an SSID as an interface name

`quickshell/settings/Tabs/Network.qml:82`

`nmcli device disconnect` receives the SSID. Track the connected interface or connection identity and pass the correct identifier. The separate Control Center backend uses yet another implementation, illustrating the cost of duplicate control paths.

### M6. Monitor reload loses VRR and mirroring — reproduced

`scripts/monitors.py:83`, `hypr/monitors.lua`

JSON stores `vrr` and `mirror`, but generated Lua omits both. An isolated serializer reproduction confirmed their absence. Saving also writes JSON and Lua sequentially without a lock or atomic replacement, and presets apply outputs sequentially without rollback. A failure can leave the live arrangement partially changed with old saved state.

Serialize the complete configuration and test reloading it, not merely inspecting JSON. Validate all requested outputs before applying a preset and define recovery for partial failures.

### M7. Video wallpaper rollback restores a still image, not the original video

`scripts/wallpaper.sh:39`, `scripts/wallpaper.sh:69`

Image application stops video units before changing Hyprpaper. On failure, rollback restores JSON/theme files and a still preview but never restarts the previous video process. Saved state can again say “video” while the screen shows a still. Applying to one output also stops a video unit targeting all outputs, affecting other displays.

Restore process state as well as files, or document and accurately persist a still-image fallback. Test an image-apply failure while a video wallpaper is already active.

### M8. Maintenance bypasses clipboard cleanup and its lock

`quickshell/settings/Tabs/Storage.qml:703`, `scripts/clipboard-action.sh:23`

Maintenance runs `cliphist wipe` directly, leaving Minimal's decoded image previews and search cache behind and bypassing the mutation lock. The shared helper already invalidates those caches. Delegate the operation to that helper.

### M9. Maintenance can report success after failure and targets inconsistent caches

`quickshell/settings/Tabs/Storage.qml:696`, `quickshell/settings/Tabs/Storage.qml:710`

Cleanup shell strings run notifications after the command regardless of its status; the last successful notification can make the process appear successful. Trash globs omit dotfiles when `trash-empty` is unavailable. Thumbnail cleanup targets `$HOME/.cache/quickshell/thumbs`, while Minimal's wallpaper thumbnails live under `$MINIMAL_CACHE/wallpaper-picker/thumbs`. Several paths ignore XDG overrides.

Use the same helpers and path definitions as the feature that owns the data, and only report success after the operation succeeds.

### M10. Audio port information is global while actions target one sink

`scripts/audio-info.py:55`, `quickshell/settings/Tabs/Sound.qml:71`

The probe combines headphone availability across all sinks and overwrites `active_port` as it walks them. The UI applies port changes to the default sink. With multiple audio devices, displayed availability/selection can belong to another sink. Return per-sink port data and bind it to the selected sink. Text parsing also assumes English `pactl` output without setting the locale.

## Installation, portability, and architecture

### M11. New Bluetooth functionality is not provisioned consistently

`quickshell/settings/Tabs/Bluetooth.qml:30`, `bootstrap.sh:14`, `deploy.sh:77`

The Send File action hard-codes this user's checkout path. The new Python D-Bus imports and Zenity picker are not explicitly checked/provisioned by deployment; the agent silently exits 0 on missing imports. Bootstrap includes PyGObject but not `python-dbus` or `zenity`. A normal successful deploy does not demonstrate that file transfer can work.

Use `MINIMAL_ROOT` consistently and add feature capability checks with actionable errors. Audit `pactl`, `powerprofilesctl`, recorder, and OCR dependencies separately rather than assuming the base desktop provides them.

### M12. Bootstrap's GPU package selection disagrees with runtime detection

`bootstrap.sh:31`, `scripts/hardware-detect.sh` Intel classification

Runtime detection distinguishes older Intel hardware and selects `i965`; bootstrap adds `intel-media-driver` for every Intel GPU without the same generation decision. NVIDIA bootstrap adds userspace packages but does not select/install a kernel driver. This is an incomplete implementation of the README's bare-metal driver-installation promise, not proof of failure on machines with drivers already installed.

Share one hardware classification between package selection and runtime setup. Validate fresh machines separately from the existing laptop.

### M13. GTK theme synchronization generates an unused artifact

`scripts/sync-theme.py:108`, `README.md:11`

The project generates `assets/gtk-accent.css`, but no deployment/session code imports or installs it into GTK configuration. The only references are generation, rollback, tests, and documentation. Its contents being correct does not make GTK applications use it.

Provide reversible integration with the actual toolkit configuration, preserving existing user CSS, or narrow the claim to “generates GTK CSS.” Toolkit/version behavior still requires a real application check.

### M14. Runtime state and lifecycle are only partly session-scoped

`scripts/paths.sh`, `scripts/popup.sh`, `scripts/session-start.sh:56`

Service names include the compositor signature, but runtime locks, popup PID files, recording state, and transfer state share a user-wide directory. Popups on two sessions can target the same ownership files. OBEX is started outside the Minimal service prefix and not tracked by the native guard. Caffeine/recording also signal Waybar processes broadly instead of the owned unit.

Separate user preferences/cache from per-session process state and decide explicitly whether OBEX is shared or owned. Do not stop shared services indiscriminately during cleanup.

### M15. Settings start/restart can create an invisible resident process

`scripts/settings.sh:36`, `quickshell/settings/Settings.qml`

`start` and `restart` launch the shell without a show IPC call, while `showing` defaults to false. Normal UI dismissal was verified to exit, but these management commands deliberately leave a hidden process awaiting IPC. Clarify their semantics or make them open the window; the blanket on-demand description currently misses this exception.

## Design, accessibility, and maintenance weaknesses

### D1. The design tokens are not yet a single source of truth

Settings applies its own opacity floor, secondary-font minimum, surface variants, and status green. Transfer errors use a separate hard-coded red; other popups use shared palette values. Hyprland rounding, Foot typography, and several popup sizes are independently configured. The UI can still diverge after changing `theme.json`.

Define semantic tokens once, explicitly document toolkit unit conversions, and make all consumers use them. Do not equate a generated file existing with the consuming app having reloaded it.

### D2. Controls have inconsistent keyboard and status behavior

The Settings `ControlArea` helps keyboard activation, but derives accessible names only from immediate text children; nested/icon-only controls can be announced as “Activate control.” Transfer buttons remain MouseAreas without equivalent keyboard behavior. Native Controls, custom rows, and separate Control Center controls have differing focus/disabled/error conventions.

Provide explicit accessible names and shared pending, disabled, failure, and focus states. Verify keyboard traversal through a scrolling page and incoming-transfer acceptance/decline.

### D3. UI and backend features have multiple independent implementations

Network, Bluetooth, audio, display, and caffeine have paths through Settings, Control Center, dedicated popups, and scripts. Their error handling, temperature/volume ranges, state sources, and lifecycle differ. Consolidate operations into shared backends while keeping compact and full interfaces if both are useful.

### D4. Storage accounting is topology-dependent

`quickshell/settings/Tabs/Storage.qml`, `findDriveUsage`

Disk use is derived by prefix-matching filesystem paths against `/dev/<disk>`. That does not resolve encrypted/LVM mapper devices and can misattribute similar disk-name prefixes. The display should use actual block-device relationships and distinguish unknown usage from zero. The existing simple SATA layout does not verify these cases.

### D5. Documentation and inactive configuration obscure the supported product

README no longer mentions the removed Dynamic Notch, but recording notifications still do. It describes GTK synchronization and a bare-metal setup more broadly than the code provides. The roadmap describes already implemented features as future work. Numerous inactive Waybar modules/styles refer to optional external tools, increasing maintenance surface without making them part of the default UI.

Mark supported defaults, optional integrations, and legacy templates explicitly. Document the persistent Bluetooth/OBEX services and retain user-selected CPU/memory modules as a preference, rather than treating their presence itself as a defect.

## Areas with stronger evidence of reliability

- Deployment and restore check ownership, preserve independently replaced configs, stage restoration, and have meaningful failure-injection tests. This audit did not reproduce a new rollback defect there.
- Clipboard decoding separates bounded previews from original-value copying, validates image dimensions, and serializes its own cache/mutation operations. The Maintenance bypass is the integration gap.
- Wallpaper search passes query/URL values as arguments, restricts download protocols, bounds downloads, and validates raster previews. External search-provider availability remains an integration risk, not a proven code regression.
- Native helpers compile cleanly. The session guard uses a PID file descriptor and an owned unit prefix rather than broad process-name termination.
- Media controls validate operations and serialize updates. Battery protection already excludes peripheral batteries and protects the lowest discharging system pack.

## Test priorities and completion criteria

1. Two independent sessions can each lock and operate popups without affecting one another.
2. Pairing requires consent; two transfer paths cannot mutate one another; cancel and timeout terminate the correct operation.
3. Idle settings change the actual service configuration across restart and login.
4. Failed recording startup produces failure, clears state, and never advertises a saved file.
5. Monitor JSON-to-Lua reload retains complete geometry, disabled state, VRR, and mirroring; failed presets recover consistently.
6. Maintenance clears the owning feature's caches and reports command failures truthfully.
7. A temporary HOME/XDG root and a relocated checkout work without references to this user's paths.
8. Fresh dependency checks exercise the new agent, picker, audio probe, power profiles, and optional recorder.
9. Theme checks verify actual consumers and keyboard navigation, not just generated text.

The passing 101-test suite is a useful baseline, but the newest transfer test is mostly file/string assertions, the recording-named test exercises OCR, and the monitor test verifies live command/JSON rather than reload semantics. Add behavioral tests at those boundaries before expanding features further.
