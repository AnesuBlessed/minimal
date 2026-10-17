//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "."

ShellRoot {
    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
    }
    PanelWindow {
        id: clipWindow
        screen: Quickshell.screens.find(s => s.name === Quickshell.env("MINIMAL_POPUP_OUTPUT")) || Quickshell.screens[0]
        color: "transparent"
        anchors.bottom: true
        implicitWidth: Math.min(720, screen.width - 24)
        implicitHeight: Math.min(540, screen.height - 48)
        WlrLayershell.namespace: "qs-clipboard"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        focusable: true
        HyprlandFocusGrab { windows: [clipWindow]; active: true; onCleared: Qt.quit() }
        ClipboardManager { anchors.fill: parent; focus: true }
    }
}
