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
        id: clipWindow
        color: "transparent"

        WlrLayershell.namespace: "qs-clipboard"
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

        // Background click dismisses clipboard manager
        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: {
                Quickshell.execDetached(["quickshell", "kill", "-p", Quickshell.shellDir])
            }
        }

        // Centered Floating Clipboard Manager
        ClipboardManager {
            id: clipboard
            anchors.centerIn: parent
            width: clipboard.s(800)
            height: clipboard.s(700)
            focus: true
        }
    }
}
