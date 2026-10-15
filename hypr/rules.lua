-- -----------------------------------------------------------------------------
-- Window & Layer Rules (Lua)
-- -----------------------------------------------------------------------------
-- Rule 4: Clean, Ergonomic Window Management

-- Floating Utilities & Dialogs
hl.window_rule({
    name  = "floating_utilities",
    match = {
        class = "^(pavucontrol|org.pulseaudio.pavucontrol|blueman-manager|nm-connection-editor|file-roller|org.gnome.FileRoller|hyprpolkitagent|xdg-desktop-portal-gtk)$",
    },
    float = true,
})

-- File Pickers
hl.window_rule({
    name  = "file_pickers",
    match = {
        title = "^(Open File|Open Folder|Save As|Choose Files)$",
    },
    float = true,
})

-- Picture-in-Picture
hl.window_rule({
    name  = "picture_in_picture",
    match = {
        title = "^(Picture-in-Picture)$",
    },
    float = true,
    pin   = true,
})


-- Waybar Layer Rule
hl.layer_rule({
    name  = "waybar_transparency",
    match = {
        namespace = "waybar",
    },
    blur         = true,
    ignore_alpha = 0.5,
})

-- Notification Layer Rule
hl.layer_rule({
    name  = "notifications",
    match = {
        namespace = "^(notifications|dunst)$",
    },
    ignore_alpha = 0.5,
})
