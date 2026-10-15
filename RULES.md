# Minimal Hyprland — Absolute Performance & Architecture Rules

This document establishes the non-negotiable engineering principles for this rice. Every configuration file, script, and component must strictly adhere to these rules to guarantee maximum performance, rock-solid stability, and minimal memory consumption across all hardware.

---

### Rule 1: Zero-Bloat Daemon Policy
* **No Runtime Overhead**: Never run background daemons written in Electron, Python, or Node.js for simple desktop tasks.
* **Native Binaries Only**: All daemons and utilities must be compiled C, C++, or Rust (e.g., `waybar`, `fuzzel`, `mako`, `foot`).
* **Kill Zombie Processes**: Any auxiliary script triggered by keybindings or events must execute and terminate immediately (`exit 0`), never running an infinite background loop.

### Rule 2: Event-Driven over Polling
* **No High-Frequency Polling**: Waybar modules and status scripts must **never** use `interval: 1` or `interval: 2` shell commands (`grep`, `awk`, `curl`).
* **Event Sockets & Signals**: Use native event listeners (Hyprland IPC socket2, PipeWire/WirePlumber events) or set poll intervals to $\ge 15\text{–}30\text{s}$ for slow-moving metrics (battery, disk, memory).

### Rule 3: GPU & Compositor Rendering Discipline
* **Variable Frame Rate (VFR) is Mandatory**: VFR must remain enabled (the default `debug:vfr = true` on Hyprland 0.55+) so frames are rendered only when on-screen content changes.
* **Zero Cost Decoration**:
  * Multi-pass blur and heavy drop-shadows are strictly disabled to prevent thermal throttling on integrated GPUs (Intel HD / AMD Vega) and reduce battery drain.
  * Rounded corners capped at modest radii ($\le 8\text{–}10\text{px}$) with zero antialiasing blur penalties.
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

### Rule 6: Non-Destructive Deployment
* **Safe Installation**: Any installation or symlinking script must automatically create a timestamped backup of existing `~/.config` directories before making any changes.
* **Reversibility**: The entire setup must be cleanly uninstallable with a single command or script.

Lockscreen frost is prepared once as a cached image when the wallpaper changes; compositor and lockscreen GPU blur remain disabled.
