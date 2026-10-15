-- -----------------------------------------------------------------------------
-- Monitors Configuration (Hardware-Agnostic)
-- -----------------------------------------------------------------------------
-- Rule 5: Universal Portability Standard
-- Automatically handles built-in laptop panels (1366x768) and any external displays.

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1.0,
})
