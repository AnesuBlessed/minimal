import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: theme
    property var tokens: ({})
    readonly property var colors: tokens.colors || ({})
    readonly property color base: "#" + (colors.base || "171c1e")
    readonly property color critical: "#" + (colors.critical || "e06c75")
    readonly property color success: "#" + (colors.success || "98c379")
    readonly property color warning: "#" + (colors.warning || "e5c07b")
    readonly property color text: "#" + (colors.text || "eef0f0")
    readonly property color accent: "#" + (colors.accent || "bec0da")
    readonly property color selection: "#" + (colors.surface || "343b3e")
    readonly property color crust: Qt.darker(base, 1.08)
    readonly property color muted: "#" + (colors.muted || "adb4b6")
    readonly property color border: Qt.rgba(accent.r, accent.g, accent.b, (tokens.opacity || {}).border ?? 0.30)
    readonly property real panelOpacity: (tokens.opacity || {}).panel ?? 0.80
    readonly property real readingOpacity: (tokens.opacity || {}).reading ?? 0.98
    readonly property color panel: Qt.rgba(base.r, base.g, base.b, panelOpacity)
    readonly property color reading: Qt.rgba(base.r, base.g, base.b, readingOpacity)
    readonly property color control: Qt.rgba(selection.r, selection.g, selection.b, (tokens.opacity || {}).control ?? 0.85)
    readonly property int panelRadius: (tokens.radius || {}).panel ?? 12
    readonly property int controlRadius: (tokens.radius || {}).control ?? 6
    readonly property int duration: (tokens.motion || {}).duration ?? 120
    readonly property string fontFamily: (tokens.font || {}).family || "JetBrainsMono Nerd Font"
    readonly property int fontBody: (tokens.font || {}).body ?? 12
    readonly property int fontSecondary: (tokens.font || {}).secondary ?? 11
    readonly property int fontTitle: (tokens.font || {}).title ?? 14
    readonly property int spaceSmall: (tokens.spacing || {}).small ?? 4
    readonly property int spaceMedium: (tokens.spacing || {}).medium ?? 8
    readonly property int spaceLarge: (tokens.spacing || {}).large ?? 12
    readonly property int spaceSection: (tokens.spacing || {}).section ?? 16
    readonly property int appIcon: (tokens.icon || {}).app ?? 28
    readonly property int systemIcon: (tokens.icon || {}).system ?? 16

    property FileView definition: FileView {
        path: (Quickshell.env("MINIMAL_ROOT") || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/minimal")) + "/theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { theme.tokens = JSON.parse(text()); }
            catch (error) { console.warn("Keeping last valid Minimal theme:", error); }
        }
    }
}
