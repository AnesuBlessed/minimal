-- -----------------------------------------------------------------------------
-- Keybindings Configuration (Lua)
-- -----------------------------------------------------------------------------
local mainMod = "SUPER"
local paths = require("paths")

local raw_bind = hl.raw_bind or hl.bind
hl.raw_bind = raw_bind
hl.bind = function(combo, action, opts)
    pcall(hl.unbind, combo)
    if opts then
        return raw_bind(combo, action, opts)
    end
    return raw_bind(combo, action)
end

-- =====================================================
-- Window Management
-- =====================================================
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + M", hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + F11", hl.dsp.window.fullscreen())

-- Move Focus Between Windows (Super + Left/Right or Super + J/K)
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + k",      hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + j",      hl.dsp.focus({ direction = "down" }))

-- Move Window Directionally (Super + Ctrl + Arrows)
hl.bind(mainMod .. " + CTRL + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + CTRL + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + CTRL + down",  hl.dsp.window.move({ direction = "down" }))

-- Resize Active Window (Super + Shift + Arrows)
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.resize({ x = -30, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.resize({ x = 30, y = 0, relative = true }),  { repeating = true })
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.resize({ x = 0, y = -30, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.resize({ x = 0, y = 30, relative = true }),  { repeating = true })

-- Workspaces Switching & Moving (Super + [1-9])
for i = 1, 9 do
    hl.bind(mainMod .. " + " .. i,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- Pocket Dimension (Special Scratchpad Workspace)
hl.bind(mainMod .. " + BackSpace",         hl.dsp.workspace.toggle_special("pocket"))
hl.bind(mainMod .. " + SHIFT + BackSpace", hl.dsp.window.move({ workspace = "special:pocket" }))

-- Mouse Actions (Move & Resize)
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- =====================================================
-- Applications & Shell Controls
-- =====================================================
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(paths.script("terminal.sh")))
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd(paths.script("launcher.sh")))
hl.bind(mainMod .. " + Tab", hl.dsp.exec_cmd(paths.script("launcher.sh") .. " window"))
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(paths.script("clipboard.sh")))
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd(paths.script("clipboard.sh") .. " --delete"))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd(paths.script("wallpaper.sh") .. " --menu"))
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd(paths.script("wallpaper.sh") .. " --random"))
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd(paths.script("wifi.sh")))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("thunar || xdg-open ~"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("firefox || xdg-open https://www.mozilla.org"))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("hyprctl reload && " .. paths.script("bar.sh") .. " reload"))

-- Power & Session Management
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd(paths.script("powermenu.sh")))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd(paths.script("lock.sh")))
hl.bind("XF86PowerOff", hl.dsp.exec_cmd(paths.script("powermenu.sh")))

-- Laptop Lid Behavior (Lock on close, wake on open)
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd(paths.script("lock.sh")), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.dpms("on"), { locked = true })

-- =====================================================
-- Media & System Controls (With Mako OSD)
-- =====================================================
-- Screenshots & Region OCR
hl.bind("Print",               hl.dsp.exec_cmd(paths.script("screenshot.sh") .. " region"))
hl.bind("SHIFT + Print",       hl.dsp.exec_cmd(paths.script("screenshot.sh") .. " edit"))
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd(paths.script("screenshot.sh") .. " full"))
hl.bind(mainMod .. " + SHIFT + O", hl.dsp.exec_cmd(paths.script("screenshot.sh") .. " ocr"))

-- Audio Controls with Mako OSD (Hardware XF86 keys + Super shortcuts + Fn fallbacks)
local vol_inc  = hl.dsp.exec_cmd(paths.script("volume.sh") .. " --inc")
local vol_dec  = hl.dsp.exec_cmd(paths.script("volume.sh") .. " --dec")
local vol_mute = hl.dsp.exec_cmd(paths.script("volume.sh") .. " --toggle-mute")
local mic_mute = hl.dsp.exec_cmd(paths.script("volume.sh") .. " --toggle-mic-mute")

hl.bind("XF86AudioRaiseVolume", vol_inc,  { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", vol_dec,  { locked = true, repeating = true })
hl.bind("XF86AudioMute",        vol_mute, { locked = true })
hl.bind("XF86AudioMicMute",     mic_mute, { locked = true })

-- Ergonomic Super keybind fallbacks for volume (works without Fn layer)
hl.bind(mainMod .. " + equal",       vol_inc,  { repeating = true })
hl.bind(mainMod .. " + minus",       vol_dec,  { repeating = true })
hl.bind(mainMod .. " + backslash",   vol_mute)
hl.bind(mainMod .. " + F3",          vol_inc,  { repeating = true })
hl.bind(mainMod .. " + F2",          vol_dec,  { repeating = true })
hl.bind(mainMod .. " + F1",          vol_mute)
hl.bind(mainMod .. " + SHIFT + M",   mic_mute)

-- Screen Brightness (Hardware XF86 keys + Super + Up/Down arrows + fallbacks)
local bright_inc = hl.dsp.exec_cmd(paths.script("brightness.sh") .. " --inc")
local bright_dec = hl.dsp.exec_cmd(paths.script("brightness.sh") .. " --dec")

hl.bind("XF86MonBrightnessUp",   bright_inc, { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", bright_dec, { locked = true, repeating = true })
hl.bind(mainMod .. " + up",      bright_inc, { repeating = true })
hl.bind(mainMod .. " + down",    bright_dec, { repeating = true })
hl.bind(mainMod .. " + Page_Up",   bright_inc, { repeating = true })
hl.bind(mainMod .. " + Page_Down", bright_dec, { repeating = true })
hl.bind(mainMod .. " + F7",      bright_inc, { repeating = true })
hl.bind(mainMod .. " + F6",      bright_inc, { repeating = true })
hl.bind(mainMod .. " + F5",      bright_dec, { repeating = true })
hl.bind(mainMod .. " + bracketright", bright_inc, { repeating = true })
hl.bind(mainMod .. " + bracketleft",  bright_dec, { repeating = true })

-- Music Play / Pause (Super + Space & Media Keys)
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioPlay",       hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",       hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",       hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
