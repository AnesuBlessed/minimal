# Minimal Hyprland — Absolute Performance & Architecture Rules

This document establishes the non-negotiable engineering principles for this rice. Every configuration file, script, and component must strictly adhere to these rules to guarantee maximum performance, rock-solid stability, minimal memory consumption across all hardware, and absolute reliability for daily driving.

---

### Rule 1: Zero-Bloat Daemon Policy
* **No Runtime Overhead**: Never run background daemons written in Electron, Python, or Node.js for simple desktop tasks.
* **Native Binaries Only**: All persistent daemons and utilities must be compiled C, C++, or Rust (e.g., `waybar`, `mako`, `foot`, `hyprpaper`, `hypridle`, `hyprlock`).
* **Kill Zombie Processes**: Any auxiliary script triggered by keybindings or events must execute and terminate immediately (`exit 0`), never running an unmanaged infinite background loop.

### Rule 2: Event-Driven over Polling
* **No High-Frequency Polling**: Waybar modules and status scripts must **never** use `interval: 1` or `interval: 2` shell commands (`grep`, `awk`, `curl`).
* **Event Sockets & Signals**: Use native event listeners (Hyprland IPC socket2, PipeWire/WirePlumber events) or set poll intervals to $\ge 15\text{–}30\text{s}$ for slow-moving metrics (battery, disk, memory).

### Rule 3: GPU & Compositor Rendering Discipline
* **Variable Frame Rate (VFR) is Mandatory**: VFR must remain enabled (`debug:vfr = true` on Hyprland 0.55+) so frames are rendered only when on-screen content changes.
* **Zero Cost Decoration**:
  * Multi-pass compositor blur and heavy drop-shadows are strictly disabled on everyday windows to prevent thermal throttling on integrated GPUs (Intel HD / AMD Vega) and reduce battery drain.
  * Rounded corners capped at modest radii ($\le 8\text{–}12\text{px}$) with zero antialiasing blur penalties.
* **Latency-Focused Animations**: Animations must either be disabled or use snappy micro-curves strictly capped at $\le 100\text{–}120\text{ms}$. No sluggish bouncy physics.

### Rule 4: Clean, Modular Configuration Architecture
* **Native Lua Engine (`hyprland.lua`)**:
  * Configuration is written in modern, native Lua (`hyprland.lua`) using the `hl.*` API to ensure long-term stability and eliminate legacy `.conf` deprecation errors.
  * `hyprland.lua` acts strictly as an orchestrator; it sources modular sub-files via `require()` (`monitors.lua`, `hardware.lua`, `looknfeel.lua`, `keybinds.lua`, `rules.lua`).
  * No monolithic 1,000-line config files.
* **Code Hygiene**:
  * Consistent indentation and section banners.
  * Preserved documentation comments explaining *why* a directive exists.
  * Zero commented-out dead code or abandoned experiments.

### Rule 5: Universal Portability Standard
* **No Hardcoded Displays**: Use universal fallback `monitor = , preferred, auto, 1` to ensure instant compatibility with any panel (built-in laptop screens, external 1080p/1440p/4K monitors).
* **Hardware-Agnostic Media Controls**: Use standard `wpctl` (WirePlumber) for audio and `brightnessctl` for backlights.
* **Conditional GPU Flags**: GPU-specific environment variables (e.g., NVIDIA flags) must be kept in a dedicated module (`env.conf` / `hardware.conf`) that fails gracefully without breaking Intel or AMD systems.

### Rule 6: Non-Destructive Deployment & Isolation
* **Safe Installation**: Any installation or symlinking script must automatically create a timestamped backup of existing `~/.config` directories before making any changes.
* **Reversibility**: The entire setup must be cleanly uninstallable with a single command or script (`./restore.sh`).
* **Complete Environment Isolation**: The installer must actively detect and neutralize conflicting host hooks (e.g. `~/.config/fish/conf.d/hyde.fish`, lingering systemd user units) so Minimal is 100% self-sufficient and never hijacked.

### Rule 7: Feature Parity & No Gutted Replacements (Anti-Shortcut Rule)
* **No Stripping Features Under the Guise of "Minimal"**: When tasked with adapting or porting a component from a reference system (such as the Hydra Wallpaper Picker or HyDE Waybar), it MUST be ported with ALL its functional capabilities intact (e.g., color sorting, color buckets, search, category filters, and full module layouts).
* **"Minimal" Means Removing Bloat, Not Removing Features**: Minimalism applies to eliminating unnecessary background daemons, theme-switching watchers, and memory leaks—NOT to deleting features the user asked for.
* **No Toy Re-implementations**: Never write a dumbed-down, barebones replacement script or QML file and claim it replaces a full-featured component. If a component is complex, take the time to port the actual logic cleanly.

### Rule 8: Zero Silent Swaps & Total Transparency
* **No Unilateral Architecture Swaps**: If the plan or user specifies a tool or design, never silently substitute a different tool without explicit user agreement.
* **Never Fake or Exaggerate Completion**: State exactly what works, what was tested, and any known limitations. Never claim a feature is complete until verified on the live system.

### Rule 9: Complete Repository Self-Containment
* **Zero Host Leakage**: Minimal must not depend on any script, binary, or configuration living outside `Projects/minimal` (aside from standard Arch Linux system packages).
* **No External Wrapper Scripts**: No scripts within Minimal may call `hyde-shell`, `~/.local/lib/hyde`, or unmanaged host dotfiles. Everything Minimal needs must be version-controlled inside the repository and deployed cleanly.

### Rule 10: Daily-Driver Live Verification
* **Real System Testing**: Because the user daily-drives this machine, every change to keybindings, bars, launchers, power menus, or lockscreens must be tested against live Wayland/Hyprland processes before declaring victory.
* **Fail-Safe Operation**: Key shortcuts for locking, terminal spawning, and power management must work reliably 100% of the time, with fail-safe fallbacks if an optional tool fails.
