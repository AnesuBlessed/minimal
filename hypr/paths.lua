-- Resolve the checkout through deployed symlinks; shell paths remain quoted.
local M = {}
function M.quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end
local file = debug.getinfo(1, "S").source:sub(2)
local pipe = assert(io.popen("readlink -f -- " .. M.quote(file)))
local resolved = pipe:read("*l")
pipe:close()
M.root = assert(resolved:match("^(.*)/hypr/[^/]+$"))
M.cache = (os.getenv("XDG_CACHE_HOME") or (os.getenv("HOME") .. "/.cache")) .. "/minimal"
function M.script(name)
    return M.quote(M.root .. "/scripts/" .. name)
end
hl.env("XDG_CONFIG_HOME", os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config"))
hl.env("MINIMAL_ROOT", M.root)
hl.env("MINIMAL_CACHE", M.cache)
return M
