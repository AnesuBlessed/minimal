# Minimal desktop audit

Audited 2026-10-17 against the current checkout and live 1366×768, scale-1 desktop.

## Assessment

Minimal still has a coherent foundation: neutral dark surfaces, one wallpaper accent, compact native utilities, and shared theme tokens. The newer Settings window introduces a second design language: tiny uppercase labels, wide tracking, repeated headings, bright outlines, extra badges, and large containers. The result is simultaneously crowded in detail and sparse in useful content.

The highest-value cleanup is Settings, followed by Waybar density and shared popup consistency. A new palette or additional effects would not address the underlying hierarchy problems.

## Scope and verification

- Visually inspected Settings Display, Sound, Network, Bluetooth, Power & Sleep, Maintenance, and Waybar on the live desktop. Returned Settings to the original Bluetooth page.
- Reviewed shared palettes, theme generation, popup layouts, settings launch/close behavior, monitor application, Hyprland geometry, native application styling, and documentation.
- Ran `python -m unittest discover -s tests -v`: **99 tests passed**, 44.231 seconds.
- Screenshots and test output are local temporary artifacts in `/tmp/minimal-audit-*`; screenshots were not added to the repository.
- Existing runtime logs contain older Row/anchor warnings. The current Sound source has already changed around those lines, so these are historical evidence, not confirmed current layout errors.
- No display modes, network connections, cleanup operations, power settings, or pairing actions were intentionally exercised. Multi-monitor behavior and fractional scaling were inspected in code, not verified on hardware. Popup/native surfaces beyond Settings and Waybar were reviewed in code, not all opened visually.

## Findings, in priority order

### 1. Settings remains alive when closed

`quickshell/settings/Settings.qml`: `hide()` and `onClosed` change visibility; neither quits nor unloads `pageLoader`. Sound, Network, Power, and Storage have unconditional repeating timers. Hidden Settings therefore retains its selected page and its polling work. This contradicts the on-demand, zero-memory-when-closed behavior described in README.

**Fix:** exit the owned Settings process on dismissal, or explicitly unload pages and document the resident-process tradeoff. The wrapper already supports starting a missing instance. Verify Escape, window close, toggle, reopen, and rapid repeated launches.

### 2. Bluetooth changes radio state while browsing

`quickshell/settings/Tabs/Bluetooth.qml`: `Component.onCompleted` invokes `tryAutoPower`; a repeating 1500 ms timer enables the adapter unless the page-local `manualOff` flag is set. Recreating the page resets that flag. Merely visiting Bluetooth can undo an off state selected elsewhere.

**Fix:** preserve observed radio state; enable only through an explicit toggle. Start discovery only while the page is open and powered. Provide distinct off, unavailable, scanning, empty, and failed states.

### 3. Monitor edits have two competing application paths

`quickshell/settings/Tabs/Display.qml`, `applyMonitorSettings`, first sends position/disable information directly to `hyprctl`, then calls `scripts/monitors.py --apply` with only name, mode, and scale. `apply_single` preserves the previously saved position, forces `disabled: False`, and defaults VRR to off. The second application can overwrite the first; dragged position is not passed to persistence. Errors are suppressed.

**Fix:** one backend operation accepting the complete intended monitor state, reporting success before updating the UI. Keep reset behavior explicit: the current reset also applies an extend-right preset. Validate position persistence, disabled outputs, VRR preservation, and failure recovery before polishing monitor interactions.

### 4. Settings bypasses the shared design system

`quickshell/settings/Theme.qml` reads colors but independently defines radii 14/18/8/4, multiple surface opacities, and extra text-opacity levels. `theme.json` defines panel/control radii 12/6 and body/secondary/title sizes 12/10/14. Settings pages mostly use hard-coded sizes instead. The outer Hyprland rounding is separately fixed at 10.

**Fix:** make Settings consume the shared palette and geometry/type tokens. Keep a small semantic set: reading surface, control surface, hover, selected, border, primary text, secondary text, accent, warning, error. Avoid layering several faint variants on top of a translucent background.

### 5. Window geometry wastes the laptop viewport

`hypr/rules.lua` forces every window titled `Settings` to 1020×660; QML requests 780×520. On this screen the rule dominates. It also matches unrelated applications with the same title. The 180 px sidebar, 22 px outside padding, divider gap, and page-specific 45/55 px right margins consume substantial space.

**Fix:** scope the rule to Minimal's application identity and use one screen-bounded size policy. Aim for a compact centered window around 800×560 on this display, with a consistent content gutter and scrolling where required. Validate at the minimum supported size and on a smaller logical viewport.

### 6. Typography and decoration obscure the hierarchy

Every Settings page repeats its title under the shared header. The header adds “configure,” a dot, and a faded icon; the sidebar adds “SYSTEM HUB,” small group captions, an active rail, a bordered selection, and number badges. Those numbers have no matching shortcut handlers in the current source. Many secondary labels are 8–10 px with reduced opacity and added letter spacing.

**Fix:** one page title, sentence-case labels, normal tracking, readable secondary text, one clear selected-navigation treatment. Remove inert shortcut badges or implement their shortcuts. Preserve the existing font initially; fix sizing and hierarchy before changing typefaces.

### 7. Page layouts need consistent rows and action placement

| Surface | Observed problem | Proposed cleanup |
| --- | --- | --- |
| Display | A fixed 260 px monitor graph dominates a single-monitor page; tiny mode labels | Compact single-display summary; show the larger arrangement canvas for multiple displays; aligned resolution, refresh, and scale rows |
| Sound | Slider values and cards crowd the right edge; duplicate title; uppercase device labels | Shared row geometry, reserved value column and scrollbar gutter, sentence-case device names |
| Network | Connect/disconnect leads each row before the network identity; large outlined toggles; technical traffic counters dominate | Name and connection state first, trailing action; put diagnostics and traffic detail below primary controls |
| Bluetooth | Pair leads the device identity; adapter reset has the same prominence as power | Name/status first, trailing pair/connect control; move reset to secondary troubleshooting |
| Power | Many equivalent outlined chips; content extends below viewport | Consistent setting rows and compact value selectors; clearer section spacing and scroll affordance |
| Maintenance | “Maintenance” becomes “STORAGE” inside the page; capacity and rescue actions are mixed | Consistent page naming; separate storage summary, cleanup, and troubleshooting; clear destructive-action treatment |

Settings' custom controls primarily use MouseArea. Only Escape and the password field's Return handling are evident in the keyboard search. Add keyboard focus, activation, visible focus states, and accessible names to shared controls.

### 8. Transparency and borders reduce crispness

The live screenshots show wallpaper shapes behind Settings text and controls. Reading surfaces need stronger separation. Bright borders appear on the window, navigation, devices, buttons, and selected states at once.

**Fix:** use a near-opaque reading surface, one subtle outer border, restrained separators, and accent primarily for selection/focus. Keep translucent styling for the small bar if desired. Use one 4/8/12/16 spacing rhythm and 6/12 control/panel radius pair.

### 9. Waybar exposes too much at equal priority

`waybar/config.jsonc` shows six separate groups and roughly twenty module slots. CPU, memory, microphone level, updates, keybind help, clipboard, menu, settings, power, connectivity, tray, and battery compete. The screenshot confirms a dense right side, while the center width depends on the window title.

**Fix:** keep workspaces, clock, audio, connectivity, battery, and tray as the primary scan path. Move diagnostics and utility shortcuts into Settings or reveal them on demand. Bound the title width and check the worst-case expanded tray and long-title layout.

### 10. Secondary surfaces and documentation have drifted

- Launcher, clipboard, keybinds, wallpaper picker, and monitor popup largely use the shared palette, but reading-heavy popups still use the 80% panel surface. Check readability against bright wallpapers.
- Foot uses font size 6, Fuzzel 10, Mako 12, and QML pixel sizes independently. These are different unit systems; validate their rendered sizes rather than simply assigning the same numeric value. Theme sync currently updates Foot colors but not its typography.
- `Super+S` now routes through `scripts/control-center.sh` to Settings; right-clicking the bar Settings icon still opens the old quick popup. `Super+P` opens another monitor UI. Establish a deliberate relationship between quick controls and full settings.
- README still advertises a Dynamic Notch and `Super+I`, although the current bar, keybind file, and Quickshell directory no longer provide that feature.
- The existing Settings test checks file presence and theme references; it does not catch hidden polling, automatic Bluetooth activation, keyboard gaps, clipping, or theme-token drift.

## Recommended implementation order

1. Correct Settings lifecycle, Bluetooth state preservation, and complete monitor-state application. Add focused behavioral regression coverage for these changes.
2. Unify Settings tokens, window geometry, navigation, header, and reading surface.
3. Introduce shared setting rows, buttons, toggles, device rows, and sliders; apply them across all six pages with keyboard support.
4. Reduce Waybar's default information density and reconcile popup entry points.
5. Verify actual rendered layouts at 1366×768 and a smaller logical viewport, long names, unavailable devices, empty lists, and bright/dark wallpapers. Update README to match the resulting behavior.

Acceptance target: one obvious hierarchy per page, no duplicated titles, readable labels, aligned trailing controls, no clipping, consistent spacing and radii, no hardware changes from simply opening a page, and no Settings process left behind after closing if the on-demand contract is retained.

---

## Post-Audit Implementation & Verification (2026-10-17)

All priority findings have been resolved and verified:

1. **Settings Lifecycle**: `Settings.qml` calls `Qt.quit()` on dismissal (`hide()` and `onClosed`). The `pageLoader` uses `active: root.showing` so subpages unload immediately. Wrapper uses atomic `flock`. Verified 0 resident processes after closing.
2. **Bluetooth Radio State**: Removed `tryAutoPower` and auto-enabling timers. Adapter state is strictly preserved; scanning occurs only while the page is visible and adapter is powered.
3. **Monitor State Application**: Added unified `--configure` command to `scripts/monitors.py` accepting complete JSON payload (position, scale, mode, vrr, disabled). Handled bool/int/string VRR representations cleanly.
4. **Design Tokens**: `Theme.qml` reads directly from `theme.json` tokens (`radius.panel`, `radius.control`, `opacity.reading`, `font.*`, `spacing.*`). Popups consume `theme.reading` (near-opaque) to eliminate wallpaper bleed.
5. **Window Geometry**: Window rule scoped to `^(Minimal Settings)$`, removed hard-coded `1020 660`. QML computes responsive dimensions bounded by display size (`820x560` max, adapts to `1366x768`).
6. **Typography & Hierarchy**: Removed duplicate headings from all subpages. Sentence-case labels, normal letter-spacing, and clear selection styling. Added keyboard navigation (`Alt + 1–6`).
7. **Consistent Page Layouts**: Device cards lead with identity/status and trail with actions. Custom controls equipped with `ControlArea.qml` focus, accessibility, and keyboard activation (`Space`/`Enter`). Sliders cleanly commit updated values.
8. **Waybar Density**: Pruned cluttered modules from default bar; center pill dedicated to `clock`, `hyprland/workspaces` moved to `left1`.
9. **Documentation Alignment**: Removed obsolete Dynamic Notch and `Super + I` references from `README.md`. Waybar settings icon documents left-click for Settings Hub and right-click for Quick Controls.
10. **Automated Regression Suite**: Expanded `tests/test_minimal.py` to **100 passing unit tests**, verifying Settings lifecycle, Bluetooth non-interference, and complete monitor geometry persistence.

