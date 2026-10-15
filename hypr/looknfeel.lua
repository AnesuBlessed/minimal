-- -----------------------------------------------------------------------------
-- Look & Feel — Performance-Tuned Minimalist Aesthetics (Lua)
-- -----------------------------------------------------------------------------
-- Rules 2 & 3: Rendering Discipline & Snappy Micro-Latency

local colors = require("colors")

hl.config({
    general = {
        gaps_in  = 4,
        gaps_out = 8,
        border_size = 1,

        col = {
            -- Dynamic palette from colors.lua
            active_border   = { colors = { colors.accent, colors.accent_subtle }, angle = 45 },
            inactive_border = colors.border_dark,
        },

        layout = "dwindle",
        resize_on_border = true,
        allow_tearing = false,
    },

    decoration = {
        rounding = 10,
        active_opacity   = 1.0,
        inactive_opacity = 0.96,

        -- Lightweight blur for Waybar frosted glass
        shadow = {
            enabled = false,
        },
        blur = {
            enabled = true,
            size = 4,
            passes = 2,
            new_optimizations = true,
            xray = false,
        },
    },

    dwindle = {
        preserve_split = true,
        smart_split    = false,
        smart_resizing = true,
    },

    misc = {
        vrr = 1,
        disable_hyprland_logo   = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
        mouse_move_enables_dpms = true,
        key_press_enables_dpms  = true,
        focus_on_activate       = true,
    },
})

-- Ultra-snappy micro transitions (~100ms)
hl.curve("microSnap", { type = "bezier", points = { {0.1, 0.9}, {0.2, 1.0} } })

hl.animation({ leaf = "windows",    enabled = true, speed = 1.2, bezier = "microSnap", style = "popin 85%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.0, bezier = "microSnap", style = "popin 85%" })
hl.animation({ leaf = "border",     enabled = true, speed = 1.0, bezier = "default" })
hl.animation({ leaf = "fade",       enabled = true, speed = 1.0, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.2, bezier = "microSnap", style = "slide" })
