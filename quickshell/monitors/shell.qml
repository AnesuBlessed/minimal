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

    readonly property string minimalRoot: Quickshell.env("MINIMAL_ROOT") || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/minimal")
    property var monitors: []

    readonly property var presets: [
        { id: "extend-right", icon: "󰍺", label: "Extend Right" },
        { id: "extend-left", icon: "󰍺", label: "Extend Left" },
        { id: "mirror", icon: "󰍹", label: "Mirror" },
        { id: "external-only", icon: "󰶐", label: "External Only" },
        { id: "internal-only", icon: "󰌢", label: "Laptop Only" }
    ]

    readonly property var scales: [1.0, 1.25, 1.5, 2.0]

    function applyJson(raw) {
        if (!raw || raw.trim() === "") return;
        try {
            const parsed = JSON.parse(raw);
            if (parsed && Array.isArray(parsed.monitors)) {
                monitors = parsed.monitors;
            }
        } catch (e) {}
    }

    function runPreset(presetId) {
        proc.command = ["python3", root.minimalRoot + "/scripts/monitors.py", "--preset", presetId];
        proc.running = true;
    }

    function applyMonitor(mon, mode, scale, vrr) {
        proc.command = [
            "python3", root.minimalRoot + "/scripts/monitors.py",
            "--apply", mon.name, mode, String(scale), vrr ? "1" : "0"
        ];
        proc.running = true;
    }

    Process {
        id: proc
        stdout: SplitParser {
            onRead: data => root.applyJson(data)
        }
    }

    Component.onCompleted: {
        applyJson(Quickshell.env("MINIMAL_MONITORS_JSON"));
    }

    PanelWindow {
        id: panel
        screen: Quickshell.screens.find(s => s.name === Quickshell.env("MINIMAL_POPUP_OUTPUT")) || Quickshell.screens[0]
        anchors.bottom: true
        implicitWidth: Math.min(560, screen.width - 24)
        implicitHeight: Math.min(390, screen.height - 48)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "minimal-monitors"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        HyprlandFocusGrab {
            windows: [panel]
            active: true
            onCleared: Qt.quit()
        }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: Qt.quit()

            Rectangle {
                anchors.fill: parent
                topLeftRadius: theme.panelRadius
                topRightRadius: theme.panelRadius
                color: theme.panel
                border.width: 1
                border.color: theme.border

                Rectangle {
                    width: 32; height: 3; radius: 1.5
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 8
                    color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.32)
                }

                Text {
                    x: 14; y: 20
                    text: "󰍹  Display Layout & Refresh Rate"
                    font.family: theme.fontFamily; font.pixelSize: theme.fontTitle; font.bold: true
                    color: theme.text
                }

                // Multi-Monitor Layout Preset Pills
                Row {
                    x: 12; y: 48
                    spacing: 6
                    Repeater {
                        model: root.presets
                        delegate: Rectangle {
                            required property var modelData
                            width: (panel.width - 24 - 24) / 5
                            height: 30
                            radius: theme.controlRadius
                            color: theme.control
                            border.width: 1
                            border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                color: theme.text
                            }

                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: root.runPreset(modelData.id)
                            }
                        }
                    }
                }

                // Per-Display Configuration Cards
                ListView {
                    x: 12; y: 88
                    width: parent.width - 24
                    height: parent.height - 98
                    model: root.monitors
                    clip: true
                    spacing: 8
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: 132
                        radius: theme.controlRadius
                        color: theme.control
                        border.width: 1
                        border.color: modelData.focused ? theme.accent : Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                        Column {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            // Header row: Connector, Description, VRR toggle
                            Item {
                                width: parent.width; height: 26
                                Row {
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8
                                    Text {
                                        text: modelData.internal ? "󰌢" : "󰍹"
                                        font.family: theme.fontFamily; font.pixelSize: 15
                                        color: theme.accent
                                    }
                                    Text {
                                        text: modelData.name + " · " + modelData.width + "×" + modelData.height + " @ " + modelData.refreshRate + "Hz"
                                        font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: true
                                        color: theme.text
                                    }
                                }

                                Rectangle {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    width: 74; height: 24
                                    radius: Math.max(4, theme.controlRadius - 1)
                                    color: modelData.vrr ? theme.accent : theme.reading
                                    border.width: 1; border.color: theme.border
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.vrr ? "VRR: ON" : "VRR: OFF"
                                        font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                        color: modelData.vrr ? theme.base : theme.muted
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.applyMonitor(modelData, "preferred", modelData.scale, !modelData.vrr)
                                    }
                                }
                            }

                            // Scale row
                            Row {
                                spacing: 6
                                Text {
                                    text: "Scale:"
                                    width: 48
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary
                                    color: theme.muted
                                }
                                Repeater {
                                    model: root.scales
                                    delegate: Rectangle {
                                        required property real modelData
                                        readonly property bool isCur: Math.abs(parent.parent.parent.modelData.scale - modelData) < 0.05
                                        width: 52; height: 24
                                        radius: Math.max(4, theme.controlRadius - 1)
                                        color: isCur ? theme.accent : theme.reading
                                        border.width: 1; border.color: theme.border
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData + "x"
                                            font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: isCur
                                            color: isCur ? theme.base : theme.text
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const mon = parent.parent.parent.modelData;
                                                root.applyMonitor(mon, "preferred", modelData, mon.vrr);
                                            }
                                        }
                                    }
                                }
                            }

                            // Modes / Refresh Rate row
                            Row {
                                spacing: 6
                                Text {
                                    text: "Mode:"
                                    width: 48
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary
                                    color: theme.muted
                                }
                                Repeater {
                                    model: modelData.modes
                                    delegate: Rectangle {
                                        required property string modelData
                                        width: modeLbl.implicitWidth + 14; height: 24
                                        radius: Math.max(4, theme.controlRadius - 1)
                                        color: theme.reading
                                        border.width: 1; border.color: theme.border
                                        Text {
                                            id: modeLbl
                                            anchors.centerIn: parent
                                            text: modelData
                                            font.family: theme.fontFamily; font.pixelSize: 10; font.bold: true
                                            color: theme.accent
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const mon = parent.parent.parent.modelData;
                                                root.applyMonitor(mon, modelData, mon.scale, mon.vrr);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
