-- -----------------------------------------------------------------------------
-- Keybindings Configuration — User Customized (Lua)
-- -----------------------------------------------------------------------------
-- Rules 1 & 4: Native C/Rust Utilities & Clean Layout

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

-- Move Focus Between Windows (Super + Arrows)
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

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
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd(paths.script("open-app.sh") .. " browser"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(paths.script("open-app.sh") .. " browser"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(paths.script("open-app.sh") .. " files"))
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd(paths.script("launcher.sh")))
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(paths.script("clipboard.sh")))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd(paths.script("wallchange.sh")))
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd(paths.script("wallchange.sh") .. " --random"))
hl.bind(mainMod .. " + U", hl.dsp.exec_cmd(paths.script("usb-menu.sh")))
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd(paths.script("control-center.sh")))
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd(paths.script("notch.sh")))
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd(paths.script("monitors.sh")))
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd(paths.script("control-center.sh") .. " wifi"))
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd(paths.script("control-center.sh") .. " bluetooth"))
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd(paths.script("control-center.sh") .. " audio"))
hl.bind(mainMod .. " + slash", hl.dsp.exec_cmd(paths.script("keybinds.sh")))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("hyprctl reload && " .. paths.script("waybar.sh") .. " --reload"))

-- Power & Session Management
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd(paths.script("powermenu.sh")))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd(paths.script("lock.sh")))
hl.bind("XF86PowerOff", hl.dsp.exec_cmd(paths.script("powermenu.sh")))

-- Laptop Lid Behavior (Safe lock on close, wake on open)
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd(paths.script("lock.sh")), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.dpms("on"), { locked = true })

-- Notification Controls (Mako / Dunst)
hl.bind(mainMod .. " + SHIFT + N",       hl.dsp.exec_cmd(paths.script("notifications.sh") .. " dismiss"))
hl.bind(mainMod .. " + SHIFT + ALT + N", hl.dsp.exec_cmd(paths.script("notifications.sh") .. " dismiss-all"))
hl.bind(mainMod .. " + ALT + N",         hl.dsp.exec_cmd(paths.script("notifications.sh") .. " restore"))
hl.bind(mainMod .. " + SHIFT + D",       hl.dsp.exec_cmd(paths.script("notifications.sh") .. " dnd"))

-- =====================================================
-- Media & System Controls
-- =====================================================
-- Screenshots, Recording & OCR
hl.bind("Print",                     hl.dsp.exec_cmd(paths.script("screenshot.sh") .. " region"))
hl.bind("SHIFT + Print",             hl.dsp.exec_cmd(paths.script("screenshot.sh") .. " edit"))
hl.bind(mainMod .. " + Print",       hl.dsp.exec_cmd(paths.script("screenshot.sh") .. " full"))
hl.bind(mainMod .. " + SHIFT + R",   hl.dsp.exec_cmd(paths.script("screenshot.sh") .. " record"))
hl.bind(mainMod .. " + SHIFT + O",   hl.dsp.exec_cmd(paths.script("screenshot.sh") .. " ocr"))

-- Audio Controls (WirePlumber)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(paths.script("media.sh") .. " volume up"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(paths.script("media.sh") .. " volume down"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd(paths.script("media.sh") .. " volume mute"),     { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd(paths.script("media.sh") .. " mic mute"),   { locked = true })

-- Screen Brightness (brightnessctl)
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(paths.script("media.sh") .. " brightness up"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(paths.script("media.sh") .. " brightness down"), { locked = true, repeating = true })

-- Music Play / Pause (Super + Space & Media Key)
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioPlay",       hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",       hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",       hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
