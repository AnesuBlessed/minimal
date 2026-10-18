//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "."

ShellRoot {
    Palette { id: theme }
    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
    }
    PanelWindow {
        id: pickerWindow
        screen: Quickshell.screens.find(s => s.name === Quickshell.env("MINIMAL_POPUP_OUTPUT")) || Quickshell.screens[0]
        color: "transparent"
        anchors.bottom: true
        implicitWidth: screen.width
        implicitHeight: Math.min(650, screen.height - 48)
        WlrLayershell.namespace: "qs-wallpaper-picker"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        HyprlandFocusGrab { windows: [pickerWindow]; active: true; onCleared: Qt.quit() }
        Rectangle {
            anchors.fill: parent
            topLeftRadius: theme.panelRadius; topRightRadius: theme.panelRadius
            color: theme.reading; border.width: 1; border.color: theme.border
            Rectangle {
                y: 9; width: 32; height: 3; radius: 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                color: theme.muted; opacity: 0.4
            }
        }
        WallpaperPicker { anchors.fill: parent; focus: true }
    }
}
