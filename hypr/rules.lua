-- -----------------------------------------------------------------------------
-- Window & Layer Rules (Lua)
-- -----------------------------------------------------------------------------

-- Battle-Tested Floating Utilities (Networking, Bluetooth, Audio, Archive)
hl.window_rule({
    name  = "floating_utilities",
    match = {
        class = "^(pavucontrol|org\\.pulseaudio\\.pavucontrol|blueman-manager|nm-connection-editor|file-roller|org\\.gnome\\.FileRoller|hyprpolkitagent|xdg-desktop-portal-gtk)$",
    },
    float  = true,
    center = true,
})

-- Modal Dimensions for Settings Dialogs
hl.window_rule({
    name  = "modal_dialog_size",
    match = {
        class = "^(blueman-manager|nm-connection-editor|pavucontrol)$",
    },
    size  = "750 500",
})

-- File Pickers & Save Dialogs
hl.window_rule({
    name  = "file_pickers",
    match = {
        title = "^(Open File|Open Folder|Save As|Choose Files|File Upload.*)$",
    },
    float  = true,
    center = true,
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

-- Satty Annotation Tool
hl.window_rule({
    name  = "satty_editor",
    match = {
        class = "^(com\\.gabm\\.satty)$",
    },
    float  = true,
    center = true,
})

-- Wallpaper Carousel (3D Coverflow)
hl.window_rule({
    name  = "wallpaper_carousel",
    match = {
        class = "^(minimal\\.wallpaper\\.carousel)$",
    },
    float       = true,
    center      = true,
})

-- Wlogout Session Menu
hl.window_rule({
    name  = "wlogout_window",
    match = {
        class = "^(wlogout)$",
    },
    float       = true,
    center      = true,
})

-- =====================================================
-- Layer Shell Rules (Frosted Glass & Alpha)
-- =====================================================
-- Rofi Launcher & Dmenu Overlay
hl.layer_rule({
    name  = "rofi_overlay",
    match = {
        namespace = "^(rofi)$",
    },
    blur         = true,
    ignore_alpha = 0.5,
})

-- Mako Notifications
hl.layer_rule({
    name  = "notifications",
    match = {
        namespace = "^(notifications|mako)$",
    },
    blur         = true,
    ignore_alpha = 0.5,
})

-- Waybar Layer & Blur
hl.layer_rule({
    name  = "waybar_layer",
    match = {
        namespace = "^(waybar)$",
    },
    blur         = true,
    ignore_alpha = 0.5,
})

-- Wlogout Power Menu
hl.layer_rule({
    name  = "wlogout_layer",
    match = {
        namespace = "^(wlogout|logout_dialog)$",
    },
    blur         = true,
    ignore_alpha = 0.5,
})
