import "../"
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Item {
    id: page

    property real marginLeft: 0
    property real marginRight: 12
    property real marginTop: 0
    property real marginBottom: 0

    property bool tapToClick: true
    property bool naturalScroll: true
    property bool disableWhileTyping: true
    property real sensitivity: 0.0
    property bool leftHanded: false

    function refresh() {
        if (!pInputGet.running) pInputGet.running = true;
    }

    property var pendingChanges: []

    function applyNext() {
        if (pInputSet.running || pendingChanges.length === 0) return;
        var next = pendingChanges.shift();
        pInputSet.command = ["bash", Quickshell.shellDir + "/../../scripts/input-config.sh", "set", next.key, String(next.value)];
        pInputSet.running = true;
    }

    function setOption(key, val) {
        // Keep only the latest value for a slider while a previous change finishes.
        pendingChanges = pendingChanges.filter(function(change) { return change.key !== key; });
        pendingChanges.push({key: key, value: val});
        applyNext();
    }

    Component.onCompleted: page.refresh()

    Process {
        id: pInputGet
        command: ["bash", Quickshell.shellDir + "/../../scripts/input-config.sh", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text.trim());
                    page.tapToClick = Boolean(data.tap_to_click);
                    page.naturalScroll = Boolean(data.natural_scroll);
                    page.disableWhileTyping = Boolean(data.disable_while_typing);
                    page.sensitivity = parseFloat(data.sensitivity) || 0.0;
                    page.leftHanded = Boolean(data.left_handed);
                } catch (e) {}
            }
        }
    }

    Process {
        id: pInputSet
        stderr: StdioCollector { id: actionError }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                Quickshell.execDetached(["notify-send", "Minimal settings", actionError.text.trim() || "Could not apply the change"]);
                page.refresh();
            }
            Qt.callLater(page.applyNext);
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text.trim());
                    page.tapToClick = Boolean(data.tap_to_click);
                    page.naturalScroll = Boolean(data.natural_scroll);
                    page.disableWhileTyping = Boolean(data.disable_while_typing);
                    page.sensitivity = parseFloat(data.sensitivity) || 0.0;
                    page.leftHanded = Boolean(data.left_handed);
                } catch (e) {}
            }
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.leftMargin: page.marginLeft
        anchors.rightMargin: page.marginRight
        anchors.topMargin: page.marginTop
        anchors.bottomMargin: page.marginBottom
        contentWidth: width
        contentHeight: content.implicitHeight + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: SettingsScrollBar {}

        Column {
            id: content
            width: Math.max(0, flick.width - 10)
            spacing: 14

            // TOUCHPAD SECTION
            Text {
                text: "Touchpad"
                color: Theme.text
                topPadding: 4
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
            }

            // Tap to Click Card
            Rectangle {
                width: parent.width
                height: 56
                radius: Theme.radius
                color: page.tapToClick ? Theme.tint(Theme.accent, 0.08) : Theme.tint("#ffffff", 0.03)
                border.width: 1
                border.color: page.tapToClick ? Theme.borderAccent : Theme.border

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.right: tapSwitch.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Text {
                        text: "󰟀"
                        font.family: Theme.iconFont
                        font.pixelSize: 18
                        color: page.tapToClick ? Theme.accent : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "Tap to Click"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                        Text {
                            text: page.tapToClick ? "Tap touchpad to register left click" : "Physical click button required"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSecondary
                        }
                    }
                }

                Rectangle {
                    id: tapSwitch
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44; height: 24; radius: 12
                    color: page.tapToClick ? Theme.accent : Theme.tint("#ffffff", 0.1)
                    border.width: 1
                    border.color: page.tapToClick ? Theme.borderAccent : Theme.borderStrong

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Rectangle {
                        width: 18; height: 18; radius: 9
                        color: page.tapToClick ? "#ffffff" : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                        x: page.tapToClick ? parent.width - width - 3 : 3
                        Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                    }
                }

                ControlArea {
                    anchors.fill: parent
                    onClicked: {
                        page.tapToClick = !page.tapToClick;
                        page.setOption("tap_to_click", page.tapToClick);
                    }
                }
            }

            // Natural Scrolling Card
            Rectangle {
                width: parent.width
                height: 56
                radius: Theme.radius
                color: page.naturalScroll ? Theme.tint(Theme.accent, 0.08) : Theme.tint("#ffffff", 0.03)
                border.width: 1
                border.color: page.naturalScroll ? Theme.borderAccent : Theme.border

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.right: natSwitch.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Text {
                        text: "󰁝"
                        font.family: Theme.iconFont
                        font.pixelSize: 18
                        color: page.naturalScroll ? Theme.accent : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "Natural Scrolling"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                        Text {
                            text: page.naturalScroll ? "Content moves in the direction of fingers" : "Traditional scroll direction"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSecondary
                        }
                    }
                }

                Rectangle {
                    id: natSwitch
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44; height: 24; radius: 12
                    color: page.naturalScroll ? Theme.accent : Theme.tint("#ffffff", 0.1)
                    border.width: 1
                    border.color: page.naturalScroll ? Theme.borderAccent : Theme.borderStrong

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Rectangle {
                        width: 18; height: 18; radius: 9
                        color: page.naturalScroll ? "#ffffff" : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                        x: page.naturalScroll ? parent.width - width - 3 : 3
                        Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                    }
                }

                ControlArea {
                    anchors.fill: parent
                    onClicked: {
                        page.naturalScroll = !page.naturalScroll;
                        page.setOption("natural_scroll", page.naturalScroll);
                    }
                }
            }

            // Disable while Typing Card
            Rectangle {
                width: parent.width
                height: 56
                radius: Theme.radius
                color: page.disableWhileTyping ? Theme.tint(Theme.accent, 0.08) : Theme.tint("#ffffff", 0.03)
                border.width: 1
                border.color: page.disableWhileTyping ? Theme.borderAccent : Theme.border

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.right: dwtSwitch.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Text {
                        text: "󰌌"
                        font.family: Theme.iconFont
                        font.pixelSize: 18
                        color: page.disableWhileTyping ? Theme.accent : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "Disable Touchpad While Typing"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                        Text {
                            text: page.disableWhileTyping ? "Locks pointer while typing to prevent palm jumps" : "Touchpad active at all times"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSecondary
                        }
                    }
                }

                Rectangle {
                    id: dwtSwitch
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44; height: 24; radius: 12
                    color: page.disableWhileTyping ? Theme.accent : Theme.tint("#ffffff", 0.1)
                    border.width: 1
                    border.color: page.disableWhileTyping ? Theme.borderAccent : Theme.borderStrong

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Rectangle {
                        width: 18; height: 18; radius: 9
                        color: page.disableWhileTyping ? "#ffffff" : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                        x: page.disableWhileTyping ? parent.width - width - 3 : 3
                        Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                    }
                }

                ControlArea {
                    anchors.fill: parent
                    onClicked: {
                        page.disableWhileTyping = !page.disableWhileTyping;
                        page.setOption("disable_while_typing", page.disableWhileTyping);
                    }
                }
            }

            // POINTER & MOUSE SECTION
            Text {
                text: "Pointer & Mouse"
                color: Theme.text
                topPadding: 8
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
            }

            // Pointer Sensitivity Slider Card
            Rectangle {
                width: parent.width
                height: 64
                radius: Theme.radius
                color: Theme.tint("#ffffff", 0.03)
                border.width: 1
                border.color: Theme.border

                Slider {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Pointer Speed"
                    icon: "󰍽"
                    resettable: true
                    resetValue: 0.5
                    displayText: (page.sensitivity >= 0 ? "+" : "") + page.sensitivity.toFixed(2)
                    value: (page.sensitivity + 1.0) / 2.0
                    onMoved: v => {
                        var realSens = (v * 2.0) - 1.0;
                        page.sensitivity = Math.round(realSens * 100) / 100;
                    }
                    onCommitted: v => {
                        var realSens = (v * 2.0) - 1.0;
                        var rounded = Math.round(realSens * 100) / 100;
                        page.sensitivity = rounded;
                        page.setOption("sensitivity", rounded);
                    }
                }
            }

            // Left Handed Card
            Rectangle {
                width: parent.width
                height: 56
                radius: Theme.radius
                color: page.leftHanded ? Theme.tint(Theme.accent, 0.08) : Theme.tint("#ffffff", 0.03)
                border.width: 1
                border.color: page.leftHanded ? Theme.borderAccent : Theme.border

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.right: lhSwitch.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Text {
                        text: "󰍾"
                        font.family: Theme.iconFont
                        font.pixelSize: 18
                        color: page.leftHanded ? Theme.accent : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "Left-Handed Mode"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                        Text {
                            text: page.leftHanded ? "Swaps primary and secondary buttons" : "Standard right-handed button layout"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSecondary
                        }
                    }
                }

                Rectangle {
                    id: lhSwitch
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44; height: 24; radius: 12
                    color: page.leftHanded ? Theme.accent : Theme.tint("#ffffff", 0.1)
                    border.width: 1
                    border.color: page.leftHanded ? Theme.borderAccent : Theme.borderStrong

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Rectangle {
                        width: 18; height: 18; radius: 9
                        color: page.leftHanded ? "#ffffff" : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                        x: page.leftHanded ? parent.width - width - 3 : 3
                        Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                    }
                }

                ControlArea {
                    anchors.fill: parent
                    onClicked: {
                        page.leftHanded = !page.leftHanded;
                        page.setOption("left_handed", page.leftHanded);
                    }
                }
            }
        }
    }
}
