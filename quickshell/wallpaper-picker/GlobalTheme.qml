pragma Singleton
import QtQuick
import "." as Design

Item {
    id: root
    Design.Palette { id: designPalette }
    property color panel: designPalette.panel
    property color reading: designPalette.reading
    property color control: designPalette.control
    property color border: designPalette.border
    property color accent: designPalette.accent
    property color muted: designPalette.muted
    property int panelRadius: designPalette.panelRadius
    property int controlRadius: designPalette.controlRadius
    property int duration: designPalette.duration
    property string fontFamily: designPalette.fontFamily
    property int fontBody: designPalette.fontBody
    property int fontSecondary: designPalette.fontSecondary
    property color base: designPalette.base
    property color mantle: designPalette.crust
    property color crust: designPalette.crust
    property color text: designPalette.text
    property color subtext0: designPalette.muted
    property color subtext1: designPalette.muted
    property color surface0: designPalette.control
    property color surface1: designPalette.border
    property color surface2: Qt.rgba(designPalette.accent.r, designPalette.accent.g, designPalette.accent.b, 0.25)
    property color overlay0: designPalette.muted
    property color overlay1: designPalette.muted
    property color overlay2: designPalette.muted
    property color blue: designPalette.accent
    property color sapphire: designPalette.accent
    property color peach: designPalette.accent
    property color green: designPalette.success
    property color red: designPalette.critical
    property color mauve: designPalette.accent
    property color pink: designPalette.accent
    property color yellow: designPalette.warning
    property color maroon: designPalette.critical
    property color teal: designPalette.accent
}
