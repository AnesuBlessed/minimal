-- -----------------------------------------------------------------------------
-- Environment Variables & Hardware Settings
-- -----------------------------------------------------------------------------
-- Wayland & XDG Integration
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Toolkit Wayland Enforcement
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")

-- Qt Wayland Optimization
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

-- Cursor Defaults
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

local M = {
    vfr = true,
    blur = true,
}

hl.config({
    debug = { vfr = M.vfr },
    decoration = { blur = { enabled = M.blur } },
})

return M
