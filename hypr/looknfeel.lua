-- -----------------------------------------------------------------------------
-- Look & Feel — Performance-Tuned Minimalist Aesthetics (Lua)
-- -----------------------------------------------------------------------------
-- Rules 2 & 3: Rendering Discipline & Snappy Micro-Latency

local colors = require("colors")
local hardware = require("hardware")

hl.config({
    general = {
        gaps_in  = 3,
        gaps_out = 6,
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
        rounding_power = 2,
        active_opacity   = 1.0,
        inactive_opacity = 0.96,

        -- Respect hardware profile blur setting (disabled by default for efficiency)
        shadow = {
            enabled = false,
        },
        blur = {
            enabled = (hardware.blur == true),
            size = 4,
            passes = 2,
            new_optimizations = true,
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

hl.animation({ leaf = "windows",    enabled = true, speed = 1.2, bezier = "microSnap", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.0, bezier = "microSnap", style = "popin 100%" })
hl.animation({ leaf = "border",     enabled = true, speed = 1.0, bezier = "default" })
hl.animation({ leaf = "fade",       enabled = true, speed = 1.0, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.2, bezier = "microSnap", style = "slide" })

-- Keep popup entrance and exit transitions brief.
hl.animation({ leaf = "layers", enabled = true, speed = 1.2, bezier = "microSnap", style = "fade" })
