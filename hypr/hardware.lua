-- -----------------------------------------------------------------------------
-- Environment Variables & Hardware Settings
-- -----------------------------------------------------------------------------
-- Rule 5: Universal Portability & Standards Compliance

-- Standard XDG Desktop Integration
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Toolkit Wayland Enforcement
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("GSK_RENDERER", "gl")

-- Qt Wayland Optimization
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

-- Cursor Defaults
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- -----------------------------------------------------------------------------
-- Dynamic Hardware & GPU Detection Integration
-- -----------------------------------------------------------------------------
local paths = require("paths")

local cache_env = paths.cache .. "/hardware.env"
local script_detect = paths.root .. "/scripts/hardware-detect.sh"

local function parse_env_line(line)
    if not line or line:match("^%s*#") or line:match("^%s*$") then
        return nil, nil
    end
    -- Matches: export KEY="VALUE" or export KEY=VALUE or KEY="VALUE" or KEY=VALUE
    local key, val = line:match("^%s*export%s+([%w_]+)=[\"']?(.-)[\"']?%s*$")
    if not key then
        key, val = line:match("^%s*([%w_]+)=[\"']?(.-)[\"']?%s*$")
    end
    return key, val
end

local function apply_flags(vars)
    for k, v in pairs(vars) do
        hl.env(k, v)
        if k == "HYPR_VFR" then
            hl.config({ debug = { vfr = (v == "true" or v == "1") } })
        elseif k == "HYPR_BLUR" then
            hl.config({ decoration = { blur = { enabled = (v == "true" or v == "1") } } })
        end
    end
end

local function load_hardware_env()
    local vars = {}
    local f = io.open(cache_env, "r")
    if f then
        for line in f:lines() do
            local k, v = parse_env_line(line)
            if k and v then
                vars[k] = v
            end
        end
        f:close()
        return vars
    end

    -- Cache missing: attempt running hardware-detect.sh --export dynamically
    local pipe = io.popen("'" .. script_detect:gsub("'", "'\\''") .. "' --export 2>/dev/null")
    if pipe then
        for line in pipe:lines() do
            local k, v = parse_env_line(line)
            if k and v then
                vars[k] = v
            end
        end
        pipe:close()
        return vars
    end

    return nil
end

local ok, detected_vars = pcall(load_hardware_env)
if ok and detected_vars and next(detected_vars) ~= nil then
    apply_flags(detected_vars)
else
    -- Graceful fallback if hardware-detect is not yet run or fails
    hl.config({
        debug = { vfr = true },
        decoration = { blur = { enabled = false } },
    })
    hl.env("HYPR_VFR", "true")
    hl.env("HYPR_BLUR", "false")
end
