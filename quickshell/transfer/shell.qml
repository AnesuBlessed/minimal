//@ pragma UseQApplication
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "."

ShellRoot {
    id: root

    Palette { id: theme }

    readonly property string minimalRuntime: Quickshell.env("MINIMAL_RUNTIME") || ("/run/user/" + (Quickshell.env("UID") || "1000") + "/minimal")
    readonly property string stateFile: minimalRuntime + "/bt-transfer.json"
    readonly property string actionFile: minimalRuntime + "/bt-transfer-action"
    readonly property string cancelFile: minimalRuntime + "/bt-transfer-cancel"

    property var transferData: ({
        id: "",
        active: false,
        direction: "incoming",
        device: "",
        filename: "",
        size: 0,
        transferred: 0,
        status: "",
        statusText: "",
        progress: 0.0
    })

    function formatBytes(bytes) {
        if (!bytes || bytes <= 0) return "0 B";
        var k = 1024;
        var sizes = ["B", "KB", "MB", "GB"];
        var i = Math.floor(Math.log(bytes) / Math.log(k));
        i = Math.min(i, sizes.length - 1);
        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i];
    }

    function readState() {
        var raw = stateReader.text();
        if (!raw || raw.trim() === "") return;
        try {
            var data = JSON.parse(raw);
            if (data && typeof data === "object") {
                if (data.id !== Quickshell.env("MINIMAL_TRANSFER_ID")) { Qt.quit(); return; }
                if (root.transferData.status !== data.status) root.actionPending = false;
                root.transferData = data;
                if (data.status === "complete" || data.status === "error" || data.status === "rejected" || data.status === "cancelled") {
                    if (!autoCloseTimer.running) autoCloseTimer.restart();
                }
            }
        } catch (e) {}
    }

    property bool actionPending: false
    function respondAction(action) {
        if (actionPending) return;
        actionPending = true;
        actionProcess.command = ["python3", Quickshell.shellDir + "/../../scripts/transfer-action.py", root.transferData.id, action];
        actionProcess.running = true;
    }
    function cancelTransfer() { respondAction("cancel"); }
    Process {
        id: actionProcess
        onExited: code => { if (code !== 0) root.actionPending = false; }
    }
    FileView {
        id: stateReader
        path: root.stateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.readState()
    }

    Timer {
        id: pollTimer
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            stateReader.reload();
            root.readState();
        }
    }

    Timer {
        id: autoCloseTimer
        interval: 3000
        repeat: false
        onTriggered: Qt.quit()
    }


    PanelWindow {
        id: win
        screen: Quickshell.screens[0]
        anchors.top: true
        anchors.right: true
        margins.top: 48
        margins.right: 18
        implicitWidth: 360
        implicitHeight: card.implicitHeight
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "minimal-bt-transfer"
        WlrLayershell.layer: WlrLayer.Overlay

        Rectangle {
            id: card
            width: parent.width
            implicitHeight: contentCol.implicitHeight + 24
            radius: theme.panelRadius
            color: theme.reading
            border.width: 1
            border.color: theme.border

            Column {
                id: contentCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 10

                // Header Row
                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: {
                            if (root.transferData.status === "complete") return "󰄬";
                            if (root.transferData.status === "error" || root.transferData.status === "rejected") return "󰅚";
                            return root.transferData.direction === "outgoing" ? "󰈔" : "󰂯";
                        }
                        font.family: theme.fontFamily
                        font.pixelSize: 16
                        color: {
                            if (root.transferData.status === "complete") return theme.accent;
                            if (root.transferData.status === "error" || root.transferData.status === "rejected") return theme.critical;
                            return theme.accent;
                        }
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        width: parent.width - 50
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            width: parent.width
                            text: {
                                if (root.transferData.status === "request") return "Incoming File Request";
                                if (root.transferData.status === "complete") return "Transfer Complete";
                                if (root.transferData.status === "error") return "Transfer Failed";
                                if (root.transferData.status === "rejected") return "Transfer Declined";
                                if (root.transferData.status === "cancelled") return "Transfer Cancelled";
                                return root.transferData.direction === "outgoing" ? "Sending File" : "Receiving File";
                            }
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontBody
                            font.bold: true
                            color: theme.text
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.transferData.device ? (root.transferData.direction === "outgoing" ? "To: " : "From: ") + root.transferData.device : "Bluetooth Transfer"
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSecondary
                            color: theme.muted
                            elide: Text.ElideRight
                        }
                    }

                    // Close button
                    Text {
                        text: "󰅖"
                        font.family: theme.fontFamily
                        font.pixelSize: 14
                        color: theme.muted
                        anchors.verticalCenter: parent.verticalCenter

                        Button {
                            background: Rectangle { color: parent.visualFocus ? theme.control : "transparent"; border.width: parent.visualFocus ? 1 : 0; border.color: theme.accent; radius: theme.controlRadius }
                            enabled: !root.actionPending
                            anchors.fill: parent
                            
                            Accessible.name: "Close transfer"
                            onClicked: { if (root.transferData.status === "request") root.respondAction("decline"); else Qt.quit(); }
                        }
                    }
                }

                // File Details Box
                Rectangle {
                    width: parent.width
                    height: 40
                    radius: theme.controlRadius
                    color: theme.control
                    border.width: 1
                    border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        Text {
                            text: "󰈔"
                            font.family: theme.fontFamily
                            font.pixelSize: 16
                            color: theme.accent
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            width: parent.width - 32
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                width: parent.width
                                text: root.transferData.filename || "Bluetooth File"
                                font.family: theme.fontFamily
                                font.pixelSize: theme.fontSecondary
                                font.bold: true
                                color: theme.text
                                elide: Text.ElideMiddle
                            }

                            Text {
                                text: {
                                    if (root.transferData.status === "transferring" && root.transferData.transferred > 0) {
                                        return root.formatBytes(root.transferData.transferred) + " / " + root.formatBytes(root.transferData.size);
                                    }
                                    return root.formatBytes(root.transferData.size);
                                }
                                font.family: theme.fontFamily
                                font.pixelSize: theme.fontSecondary
                                color: theme.muted
                            }
                        }
                    }
                }

                // Progress Bar (when transferring)
                Column {
                    width: parent.width
                    visible: root.transferData.status === "transferring" || root.transferData.status === "complete"
                    spacing: 4

                    Item {
                        width: parent.width
                        height: 16
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round((root.transferData.progress || 0) * 100) + "%"
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSecondary
                            font.bold: true
                            color: theme.accent
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.transferData.status === "complete" ? "Finished" : "Transferring..."
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSecondary
                            color: theme.muted
                        }
                    }

                    // Minimal track and fill
                    Rectangle {
                        width: parent.width
                        height: 6
                        radius: 3
                        color: theme.control

                        Rectangle {
                            height: parent.height
                            width: Math.max(4, Math.min(parent.width, parent.width * (root.transferData.progress || 0)))
                            radius: 3
                            color: theme.accent

                            Behavior on width {
                                NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                            }
                        }
                    }
                }

                // Authorization Buttons (when receiving request)
                Row {
                    width: parent.width
                    visible: root.transferData.status === "request"
                    spacing: 8

                    Rectangle {
                        width: (parent.width - 8) / 2
                        height: 32
                        radius: theme.controlRadius
                        color: declineArea.containsPress ? theme.surfaceAlt : (declineArea.containsMouse ? theme.control : (theme.reading || "transparent"))
                        border.width: 1
                        border.color: theme.border

                        Text {
                            anchors.centerIn: parent
                            text: "DECLINE"
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSecondary
                            font.bold: true
                            color: theme.muted
                        }

                        MouseArea {
                            id: declineArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !root.actionPending
                            onClicked: root.respondAction("decline")
                        }
                    }

                    Rectangle {
                        width: (parent.width - 8) / 2
                        height: 32
                        radius: theme.controlRadius
                        color: acceptArea.containsPress ? Qt.darker(theme.accent, 1.15) : (acceptArea.containsMouse ? Qt.lighter(theme.accent, 1.1) : theme.accent)

                        Text {
                            anchors.centerIn: parent
                            text: "ACCEPT"
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSecondary
                            font.bold: true
                            color: theme.base
                        }

                        MouseArea {
                            id: acceptArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !root.actionPending
                            onClicked: root.respondAction("accept")
                        }
                    }
                }

                // Cancel Button (when transferring)
                Rectangle {
                    width: parent.width
                    height: 28
                    visible: root.transferData.status === "transferring"
                    radius: theme.controlRadius
                    color: cancelArea.containsPress ? theme.surfaceAlt : (cancelArea.containsMouse ? theme.control : "transparent")
                    border.width: 1
                    border.color: theme.border

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel Transfer"
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontSecondary
                        font.bold: true
                        color: theme.muted
                    }

                    MouseArea {
                        id: cancelArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !root.actionPending
                        onClicked: root.cancelTransfer()
                    }
                }
            }
        }
    }
}
