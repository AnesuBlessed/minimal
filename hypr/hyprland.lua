-- =============================================================================
--  MINIMAL — HYPRLAND MASTER CONFIGURATION (LUA)
-- =============================================================================
--  Design principles summarized in README.md:
--  - Future-proof native Lua engine (Hyprland 0.56+)
--  - Zero runtime bloat, VFR enabled for low latency and cool iGPU operation
--  - Event-driven architecture with native C utilities
-- =============================================================================

-- Add script directory to Lua package path for clean modular require()
local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
local config_hypr = (os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")) .. "/hypr/"
package.path = script_dir .. "?.lua;" .. config_hypr .. "?.lua;" .. package.path

-- Invalidate component cache so re-evaluating hyprland.lua always reloads all modules
package.loaded["paths"] = nil
package.loaded["monitors"] = nil
package.loaded["hardware"] = nil
package.loaded["looknfeel"] = nil
package.loaded["keybinds"] = nil
package.loaded["rules"] = nil
package.loaded["colors"] = nil
package.loaded["hyprland"] = nil

-- --- Modular Component Inclusions ---
local paths = require("paths")
require("monitors")
require("hardware")
require("looknfeel")
require("keybinds")
require("rules")

-- --- Input Devices (Keyboard & Touchpad) ---
hl.config({
    input = {
        kb_layout    = "us",
        follow_mouse = 1,
        sensitivity  = 0,

        touchpad = {
            natural_scroll       = true,
            disable_while_typing = true,
        },
    },
})

-- The session helper starts native daemons once and exits.
hl.on("hyprland.start", function ()
    hl.exec_cmd(paths.script("session-start.sh"))
end)
