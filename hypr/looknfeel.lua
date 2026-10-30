-- -----------------------------------------------------------------------------
-- Look & Feel — Performance-Tuned Obsidian Aesthetic (Lua)
-- -----------------------------------------------------------------------------
local colors = require("colors")
local hardware = require("hardware")

hl.config({
    general = {
        gaps_in  = 3,
        gaps_out = 8,
        border_size = 2,

        col = {
            active_border   = { colors = { colors.accent, colors.accent_subtle }, angle = 45 },
            inactive_border = colors.border_dark,
        },

        layout = "dwindle",
        resize_on_border = true,
        allow_tearing = false,
    },

    decoration = {
        rounding = 12,
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled = false,
        },
        blur = {
            enabled = (hardware.blur ~= false),
            size = 4,
            passes = 1,
            new_optimizations = true,
            ignore_opacity = true,
            xray = false,
        },
    },

    debug = {
        vfr = (hardware.vfr ~= false),
    },

    dwindle = {
        preserve_split = true,
        smart_split    = false,
        smart_resizing = true,
    },

    misc = {
        vrr = 0,
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        force_default_wallpaper  = 0,
        mouse_move_enables_dpms  = true,
        key_press_enables_dpms   = true,
        focus_on_activate        = true,
        -- Lets lock.sh relaunch hyprlock if it crashes while the session is locked.
        allow_session_lock_restore = true,
    },

    cursor = {
        no_hardware_cursors = false,
        enable_hyprcursor = true,
        sync_gsettings_theme = true,
    },
})

-- Snappy, low-latency micro transitions (~120ms)
hl.curve("microSnap", { type = "bezier", points = { {0.16, 1.0}, {0.3, 1.0} } })

hl.animation({ leaf = "windows",    enabled = true, speed = 1.4, bezier = "microSnap", style = "popin 80%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.2, bezier = "microSnap", style = "popin 80%" })
hl.animation({ leaf = "border",     enabled = true, speed = 1.0, bezier = "default" })
hl.animation({ leaf = "fade",       enabled = true, speed = 1.0, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.4, bezier = "microSnap", style = "slide" })
hl.animation({ leaf = "layers",     enabled = true, speed = 1.2, bezier = "microSnap", style = "fade" })
