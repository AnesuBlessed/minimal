import QtQuick

// Keyboard and pointer activation for the custom Settings controls.
MouseArea {
    id: control
    property string label: {
        function collect(item) {
            var result = [];
            if (!item || item === control || item.visible === false) return result;
            if (typeof item.text === "string" && /[A-Za-z0-9]/.test(item.text)) result.push(item.text);
            if (item.children) for (var i = 0; i < item.children.length; i++) result = result.concat(collect(item.children[i]));
            return result;
        }
        return collect(parent).join(" ") || "Activate control";
    }
    activeFocusOnTab: enabled && visible
    cursorShape: Qt.PointingHandCursor
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: clicked(null)
    Keys.onSpacePressed: clicked(null)
    Keys.onReturnPressed: clicked(null)
    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        visible: control.activeFocus
        color: "transparent"
        radius: Theme.radiusSm
        border.width: 1
        border.color: Theme.accent
    }
}
