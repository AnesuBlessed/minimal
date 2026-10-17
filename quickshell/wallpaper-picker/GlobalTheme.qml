pragma Singleton
import QtQuick
import "." as Design

Item {
    id: root
    Design.Palette { id: designPalette }
    property color panel: designPalette.panel
    property color control: designPalette.control
    property color border: designPalette.border
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
    property color surface0: designPalette.selection
    property color surface1: designPalette.selection
    property color surface2: designPalette.selection
    property color overlay0: designPalette.muted
    property color overlay1: designPalette.muted
    property color overlay2: designPalette.muted
    property color blue: designPalette.accent
    property color sapphire: designPalette.accent
    property color peach: designPalette.accent
    property color green: designPalette.accent
    property color red: designPalette.accent
    property color mauve: designPalette.accent
    property color pink: designPalette.accent
    property color yellow: designPalette.accent
    property color maroon: designPalette.accent
    property color teal: designPalette.accent
}
