-- =============================================================================
--  MINIMAL — PATH RESOLUTION (LUA)
-- =============================================================================
local M = {}

function M.quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

-- Lua treats "" as true, so empty XDG_* values must fall back explicitly.
local function env(name, fallback)
    local value = os.getenv(name)
    if value == nil or value == "" then return fallback end
    return value
end

local home = env("HOME", "")
local file = debug.getinfo(1, "S").source:sub(2)

-- Resolve the file before deriving the checkout root, including ~/.config symlinks.
local p = io.popen("readlink -f -- " .. M.quote(file))
local resolved = p and p:read("*l")
if p then p:close() end
M.root = assert(resolved and resolved:match("^(.*)/hypr/[^/]+$"), "Cannot resolve Minimal checkout")

M.cache = env("XDG_CACHE_HOME", home .. "/.cache") .. "/minimal"
M.state = env("XDG_STATE_HOME", home .. "/.local/state") .. "/minimal"
-- Mirrors scripts/paths.sh: never a shared /tmp fallback.
M.runtime = env("XDG_RUNTIME_DIR", M.cache .. "/runtime") .. "/minimal"

function M.script(name)
    return M.quote(M.root .. "/scripts/" .. name)
end

hl.env("XDG_CONFIG_HOME", env("XDG_CONFIG_HOME", home .. "/.config"))
hl.env("MINIMAL_ROOT", M.root)
hl.env("MINIMAL_CACHE", M.cache)
hl.env("MINIMAL_STATE", M.state)
hl.env("MINIMAL_RUNTIME", M.runtime)

return M
