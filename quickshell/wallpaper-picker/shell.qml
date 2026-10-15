//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Wayland
import "."

ShellRoot {
    id: root

    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
        function onReloadFailed(errorString) { Quickshell.inhibitReloadPopup() }
    }

    PanelWindow {
        id: pickerWindow
        color: "transparent"

        WlrLayershell.namespace: "qs-wallpaper-picker"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        focusable: true

        implicitWidth: Screen.width
        implicitHeight: Screen.height

        // Darkened backdrop overlay
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.04, 0.04, 0.06, 0.70)
        }

        // Background click dismisses the picker
        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: {
                Quickshell.execDetached(["quickshell", "kill", "-p", Quickshell.shellDir])
            }
        }

        // Centered Wallpaper Picker
        WallpaperPicker {
            id: picker
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: picker.s(650)
            focus: true
        }
    }
}
