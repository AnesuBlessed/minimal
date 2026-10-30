-- Wallpaper palette is generated per user; use bundled colors before first apply.
local state = os.getenv("XDG_STATE_HOME")
if not state or state == "" then state = os.getenv("HOME") .. "/.local/state" end
local ok, generated = pcall(dofile, state .. "/minimal/theme/colors.lua")
if ok and type(generated) == "table" then return generated end

-- =============================================================================
--  MINIMAL — CENTRAL PALETTE SYSTEM (OBSIDIAN GLASS)
-- =============================================================================
local colors = {
    accent        = "rgba(ca9ee6ff)",
    accent_subtle = "rgba(aac7f0cc)",
    border_dark   = "rgba(3a4e6b99)",
    bg_dark       = "0x0f1a2a",
    text_main     = "0xcce1ff",
}

return colors
