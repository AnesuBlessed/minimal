import QtQuick
import QtQuick.Controls

ScrollBar {
    policy: ScrollBar.AsNeeded
    width: 4
    visible: size < 1
    background: Rectangle { color: "transparent" }
    contentItem: Rectangle {
        implicitWidth: 4
        radius: 2
        color: Theme.textDim
        opacity: parent.active ? 0.7 : 0.3
    }
}
