-- =============================================================================
--  MINIMAL — PATH RESOLUTION (LUA)
-- =============================================================================
local M = {}

function M.quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local home = os.getenv("HOME") or ""
local file = debug.getinfo(1, "S").source:sub(2)

-- Resolve root directory from script location or environment
M.root = os.getenv("MINIMAL_ROOT") or file:match("^(.*)/hypr/[^/]+$")
if not M.root then
    local p = io.popen("readlink -f -- " .. M.quote(file) .. " 2>/dev/null")
    if p then
        local res = p:read("*l")
        p:close()
        if res then M.root = res:match("^(.*)/hypr/[^/]+$") end
    end
end
M.root = M.root or (home .. "/Projects/minimal")

M.cache = (os.getenv("XDG_CACHE_HOME") or (home .. "/.cache")) .. "/minimal"

function M.script(name)
    return M.quote(M.root .. "/scripts/" .. name)
end

hl.env("XDG_CONFIG_HOME", os.getenv("XDG_CONFIG_HOME") or (home .. "/.config"))
hl.env("MINIMAL_ROOT", M.root)
hl.env("MINIMAL_CACHE", M.cache)

return M
