import QtQuick
import Quickshell
import Quickshell.Io
pragma Singleton

QtObject {
    id: root

    property var tokens: ({})
    readonly property var colors: tokens.colors || ({})
    readonly property var opacities: tokens.opacity || ({})

    readonly property color baseColor: "#" + (colors.base || "171c1e")
    readonly property color accentColor: "#" + (colors.accent || "bec0da")
    readonly property color surfaceColor: "#" + (colors.surface || "343b3e")
    readonly property color textColor: "#" + (colors.text || "eef0f0")
    readonly property color mutedColor: "#" + (colors.muted || "adb4b6")

    readonly property int radius: 14
    readonly property int radiusLg: 18
    readonly property int radiusSm: 8
    readonly property int radiusXs: 4

    readonly property string fontFamily: (tokens.font || {}).family || "JetBrainsMono Nerd Font"
    readonly property string displayFont: fontFamily
    readonly property string monoFont: fontFamily
    property string iconFont: "JetBrainsMono Nerd Font"

    readonly property int animFast: (tokens.motion || {}).duration ?? 120
    readonly property int animMed: animFast + 60
    readonly property int animSlow: animFast + 160

    readonly property color glass: Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.92)
    readonly property color bg: Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.85)
    readonly property color bgPanel: Qt.rgba(surfaceColor.r, surfaceColor.g, surfaceColor.b, 0.40)
    readonly property color bgCard: Qt.rgba(surfaceColor.r, surfaceColor.g, surfaceColor.b, 0.55)
    readonly property color bgElev: Qt.rgba(surfaceColor.r, surfaceColor.g, surfaceColor.b, 0.70)
    readonly property color bgHover: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.16)
    readonly property color bgActive: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.28)

    readonly property color text: textColor
    readonly property color textSoft: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.88)
    readonly property color textDim: mutedColor
    readonly property color textFaint: Qt.rgba(mutedColor.r, mutedColor.g, mutedColor.b, 0.65)
    readonly property color textGhost: Qt.rgba(mutedColor.r, mutedColor.g, mutedColor.b, 0.35)

    readonly property color accent: accentColor
    readonly property color accentSoft: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.85)
    readonly property color accentGlow: accentColor
    readonly property color accent2: Qt.rgba(surfaceColor.r, surfaceColor.g, surfaceColor.b, 0.90)

    readonly property color ringOuter: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.18)
    readonly property color ringInner: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.08)
    readonly property color border: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, (opacities.border ?? 0.25))
    readonly property color borderStrong: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.40)
    readonly property color borderAccent: accentColor

    readonly property color danger: "#" + (colors.critical || "e06c75")
    readonly property color ok: "#4ade80"
    readonly property color trackBg: Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.60)

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function tint(hex, a) {
        var c = Qt.color(hex);
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    property FileView definition: FileView {
        path: (Quickshell.env("MINIMAL_ROOT") || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/minimal")) + "/theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.tokens = JSON.parse(text()); }
            catch (error) {}
        }
    }
}