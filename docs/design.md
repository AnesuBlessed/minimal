# Minimal design conventions

The desktop uses a dark blue surface (`#0f1a2a`), raised cards (`#182234`),
light text (`#cce1ff`), lavender focus (`#ca9ee6`), and blue borders (`#506182`).
The user's pink selection accent is retained in Rofi and Waybar. Transparency
must preserve text readability over a bright wallpaper.

Use JetBrainsMono Nerd Font, 10–12pt text depending on the toolkit, 12px panel
corners, 16px power cards, and a 2px visible keyboard-focus border. Status icons
must expose a descriptive tooltip; destructive actions must have readable text.
Menus keep search visible and selected items distinct from hover-only states.

The bar keeps the repository's existing 17 layouts, 10px typography, pill/leaf
geometry, spacing, and user palette. Do not replace these with a new default
composition. The bundled `groups/` and `defaults.css` files own those rules.
Functional module repairs must retain the existing group placement.

Launcher width is relative to the display; short-screen overrides reduce the
wallpaper pane and list height. Clipboard placement follows the generated bar
position. Power cards keep the same geometry on focus to avoid layout movement.

A visual release review should cover 1366×768, 1920×1080, and a fractional-scale
display with bright and dark wallpapers. Check keyboard-only navigation,
empty results, long application names, missing hardware, and critical battery
states. Screenshots must be taken from a running test session, not mocked up as
proof of runtime behavior.
