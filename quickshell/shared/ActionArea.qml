import QtQuick

// Keep custom pointer controls reachable by keyboard and assistive technology.
MouseArea {
    id: control
    required property string label
    required property color focusColor
    activeFocusOnTab: enabled && visible
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: if (enabled) clicked(null)
    Keys.onSpacePressed: if (enabled) clicked(null)
    Keys.onReturnPressed: if (enabled) clicked(null)
    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        visible: control.activeFocus
        color: "transparent"
        radius: 4
        border.width: 1
        border.color: control.focusColor
    }
}
