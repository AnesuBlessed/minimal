-- -----------------------------------------------------------------------------
-- Monitors Configuration (Hardware-Agnostic)
-- -----------------------------------------------------------------------------
-- Rule 5: Universal Portability Standard
-- Automatically handles built-in laptop panels (1366x768) and any external displays.

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1.0,
})

local state_dir = os.getenv("MINIMAL_STATE") or ((os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")) .. "/minimal")
local saved_monitors = state_dir .. "/monitors.lua"
local f = io.open(saved_monitors, "r")
if f then
    f:close()
    pcall(dofile, saved_monitors)
end
