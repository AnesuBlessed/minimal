# Minimal Design Settings

This document describes settings present in the repository. It does not guarantee a particular rendered size, contrast ratio, or frame rate.

## Colors

The bundled Hyprland, Mako, Foot, Hyprlock, and wlogout templates use an obsidian-style palette including:

| Role | Template color |
| --- | --- |
| Background | `#0f1a2a` |
| Surface | `#182234` |
| Foreground | `#cce1ff` |
| Muted text | `#7a92c2` |
| Border | `#506182` |
| Accent | `#ca9ee6` |
| Warning/danger | `#e06c75` |

These are template values, not a universal active palette. [Waybar's fallback theme](../waybar/theme.css) and [Rofi's fallback theme](../rofi/theme.rasi) use purple/pink colors. [theme.rs](../native/src/theme.rs) derives replacement colors from a wallpaper and preserves semantic warning colors in templates.

Generated Waybar panel backgrounds use 0.88 alpha; Rofi's main background uses hexadecimal `eb` alpha. The wlogout scrim uses 0.85 alpha. Transparency, blur, and the wallpaper affect perceived readability; no automatic contrast-ratio measurement is implemented.

## Typography

- Waybar uses `JetBrainsMono Nerd Font` at 10px in `waybar/includes/global.css`.
- Rofi themes specify `JetBrainsMono Nerd Font 10`.
- wlogout uses the same font family at 13px, bold.
- The GTK carousel draws text through Cairo at sizes specified in `native/carousel.c`; there is no shared heading/body token scale across all overlays.

## Geometry

- Hyprland window rounding is 12, with 2px borders, inner gaps of 3, and outer gaps of 8 in [looknfeel.lua](../hypr/looknfeel.lua).
- The default custom Waybar configuration requests 38px height. Preset `01` requests 10px; module content and CSS can require more space.
- Rofi launcher and selector windows use 18px corner radii. The clipboard window uses 1.2em.
- wlogout uses a centered floating horizontal dock (`-b 6`) with rounded rectangular cards (20px radii), 2px borders, resolution-adaptive vertical/horizontal margins, and 12px column spacing. Focus/hover highlights with dynamic wallpaper accent glow.

## Motion and rendering

Hyprland defines a `microSnap` bezier curve and separate window, fade, workspace, border, and layer animations. The configuration disables tearing, sets VRR to 0, disables window shadows, and enables a single blur pass unless the hardware settings disable blur. These settings do not establish measured latency or frame pacing across hardware.

The GTK carousel uses a GTK frame-clock tick callback and moves 24% of the remaining distance per tick until it reaches its threshold. It defaults to the Cairo renderer when `GSK_RENDERER` is unset. It does not use the previously documented exponential time-based interpolation formula.

wlogout button transitions use `120ms ease-out`. Waybar has its own CSS transitions. There is no single animation engine or timing guarantee shared by all desktop utilities.
