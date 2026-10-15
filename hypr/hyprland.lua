-- =============================================================================
--  MINIMAL — HYPRLAND MASTER CONFIGURATION (LUA)
-- =============================================================================
--  Strictly adheres to RULES.md:
--  - Future-proof native Lua engine (Hyprland 0.50+ / 0.56+)
--  - Zero runtime bloat, VFR enabled for low latency and cool iGPU operation
--  - Event-driven architecture with native C utilities
-- =============================================================================

-- Add script directory to Lua package path for clean modular require()
local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = script_dir .. "?.lua;" .. package.path

-- --- Modular Component Inclusions ---
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

-- --- Core Autostart Daemons (Rule 1: Native C/Rust Only) ---
hl.on("hyprland.start", function ()
    -- 1. Polkit Authentication Agent
    hl.exec_cmd("/usr/lib/hyprpolkitagent/hyprpolkitagent || /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

    -- 2. Foot Terminal Server (Instant footclient launch with ~0 MB startup RAM)
    hl.exec_cmd("foot --server")

    -- 3. Status Bar & Notifications
    hl.exec_cmd("waybar")
    hl.exec_cmd("mako")

    -- 4. Wallpaper & Power / Idle
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("hypridle")

    -- 5. Wayland Clipboard History (cliphist)
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
