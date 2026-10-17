-- -----------------------------------------------------------------------------
-- Window & Layer Rules (Lua)
-- -----------------------------------------------------------------------------
-- Rule 4: Clean, Ergonomic Window Management

-- Floating Utilities & Dialogs (Curved 10px edges inherited from decoration.rounding)
hl.window_rule({
    name  = "floating_utilities",
    match = {
        class = "^(pavucontrol|org\\.pulseaudio\\.pavucontrol|blueman-manager|blueman-applet|blueman-services|blueman-adapters|nm-connection-editor|nm-applet|iwgtk|overskride|blueberry\\.py|file-roller|org\\.gnome\\.FileRoller|hyprpolkitagent|xdg-desktop-portal-gtk)$",
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
    blur         = false,
    ignore_alpha = 0.5,
})

-- Notification Layer Rule
hl.layer_rule({
    name  = "notifications",
    match = {
        namespace = "^(notifications|mako)$",
    },
    ignore_alpha = 0.5,
})

-- Launcher slides in from the bottom edge.
hl.layer_rule({
    name  = "launcher_bottom",
    match = {
        namespace = "^(launcher|fuzzel|minimal-launcher|qs-clipboard|qs-wallpaper-picker)$",
    },
    animation    = "slide bottom",
    blur         = false,
    ignore_alpha = 0.5,
})

-- Quickshell Settings Window
hl.window_rule({
    name  = "quickshell_settings",
    match = {
        title = "^(Settings)$",
    },
    float  = true,
    center = true,
    size   = "1020 660",
})

