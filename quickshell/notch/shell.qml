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

    property var stateData: ({
        recording: { active: false, elapsed: "00:00", path: "" },
        media: { active: false, status: "Stopped", player: "Media", title: "Nothing Playing", artist: "Start playback in any media app", album: "", artUrl: "", position: 0, length: 0, positionStr: "0:00", lengthStr: "0:00" },
        weather: { location: "Local Weather", tempC: "--", feelsLikeC: "--", condition: "Loading…", icon: "󰖐", humidity: "--", windKmph: "--", forecast: [] }
    })

    function applyJson(raw) {
        if (!raw || raw.trim() === "") return;
        try {
            const parsed = JSON.parse(raw);
            if (parsed && typeof parsed === "object") {
                stateData = {
                    recording: parsed.recording || stateData.recording,
                    media: Object.assign({
                        active: false, status: "Stopped", player: "Media",
                        title: "Nothing Playing", artist: "Start playback in any media app",
                        album: "", artUrl: "", position: 0, length: 0,
                        positionStr: "0:00", lengthStr: "0:00"
                    }, parsed.media || {}),
                    weather: Object.assign({
                        location: "Local Weather", tempC: "--", feelsLikeC: "--",
                        condition: "Unavailable", icon: "󰖐", humidity: "--",
                        windKmph: "--", forecast: []
                    }, parsed.weather || {})
                };
            }
        } catch (e) {}
    }

    function mediaAction(action) {
        Quickshell.execDetached(["playerctl", action]);
        refreshTimer.restart();
    }

    function refreshWeather() {
        weatherRefreshProc.running = true;
    }

    function stopRecording() {
        Quickshell.execDetached([minimalRoot + "/scripts/screenshot.sh", "record"]);
        Qt.quit();
    }

    Process {
        id: pollProc
        command: ["python3", root.minimalRoot + "/scripts/notch-status.py", "--popup-json"]
        stdout: SplitParser {
            onRead: data => root.applyJson(data)
        }
    }

    Process {
        id: weatherRefreshProc
        command: ["python3", root.minimalRoot + "/scripts/notch-status.py", "--refresh-weather"]
        onExited: pollProc.running = true
    }

    Timer {
        id: refreshTimer
        interval: 1500
        running: true
        repeat: true
        onTriggered: pollProc.running = true
    }

    Component.onCompleted: {
        applyJson(Quickshell.env("MINIMAL_NOTCH_JSON"));
    }

    PanelWindow {
        id: panel
        screen: Quickshell.screens.find(s => s.name === Quickshell.env("MINIMAL_POPUP_OUTPUT")) || Quickshell.screens[0]
        anchors.top: true
        margins.top: 6
        implicitWidth: Math.min(480, screen.width - 24)
        implicitHeight: root.stateData.recording.active ? 356 : 312
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "minimal-notch"
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
            Keys.onSpacePressed: root.mediaAction("play-pause")

            Rectangle {
                anchors.fill: parent
                radius: theme.panelRadius
                color: theme.panel
                border.width: 1
                border.color: theme.border

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    // Active Recording Banner (if recording)
                    Rectangle {
                        visible: root.stateData.recording.active
                        width: parent.width
                        height: 34
                        radius: theme.controlRadius
                        color: Qt.rgba(0.92, 0.28, 0.34, 0.22)
                        border.width: 1
                        border.color: Qt.rgba(0.95, 0.35, 0.40, 0.65)

                        Row {
                            anchors.left: parent.left; anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                text: "󰑊"; font.family: theme.fontFamily; font.pixelSize: 14
                                color: "#f38ba8"
                            }
                            Text {
                                text: "Recording · " + root.stateData.recording.elapsed
                                font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: true
                                color: theme.text
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 68; height: 22
                            radius: Math.max(4, theme.controlRadius - 2)
                            color: "#f38ba8"
                            Text {
                                anchors.centerIn: parent
                                text: "Stop"
                                font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                color: theme.base
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.stopRecording()
                            }
                        }
                    }

                    // Media / Now Playing Card
                    Rectangle {
                        width: parent.width
                        height: 118
                        radius: theme.controlRadius
                        color: theme.control
                        border.width: 1
                        border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                        // Art / Disc Badge
                        Rectangle {
                            id: artBox
                            x: 10; y: 10
                            width: 64; height: 64
                            radius: theme.controlRadius
                            color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.16)
                            border.width: 1
                            border.color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.32)
                            clip: true

                            Image {
                                id: albumArt
                                anchors.fill: parent
                                source: root.stateData.media.artUrl || ""
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !albumArt.visible
                                text: root.stateData.media.status === "Playing" ? "󰝚" : "󰎆"
                                font.family: theme.fontFamily; font.pixelSize: 26
                                color: theme.accent
                            }
                        }

                        // Track Metadata
                        Column {
                            x: 84; y: 10
                            width: parent.width - 200
                            spacing: 3

                            Row {
                                spacing: 6
                                Rectangle {
                                    width: playerBadge.implicitWidth + 10; height: 18
                                    radius: 4
                                    color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.18)
                                    Text {
                                        id: playerBadge
                                        anchors.centerIn: parent
                                        text: (root.stateData.media.player || "MPRIS").toUpperCase()
                                        font.family: theme.fontFamily; font.pixelSize: 9; font.bold: true
                                        color: theme.accent
                                    }
                                }
                                Text {
                                    text: root.stateData.media.status
                                    font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary
                                    color: theme.muted
                                }
                            }

                            Text {
                                width: parent.width
                                text: root.stateData.media.title || "Nothing Playing"
                                elide: Text.ElideRight
                                font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: true
                                color: theme.text
                            }

                            Text {
                                width: parent.width
                                text: root.stateData.media.artist || "Open Spotify, MPV, or Browser media"
                                elide: Text.ElideRight
                                font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary
                                color: theme.muted
                            }
                        }

                        // Transport Buttons
                        Row {
                            anchors.right: parent.right; anchors.rightMargin: 10
                            y: 22
                            spacing: 6

                            Repeater {
                                model: [
                                    { icon: "󰒮", act: "previous", primary: false },
                                    { icon: root.stateData.media.status === "Playing" ? "󰏤" : "󰐊", act: "play-pause", primary: true },
                                    { icon: "󰒭", act: "next", primary: false }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: modelData.primary ? 34 : 28
                                    height: modelData.primary ? 34 : 28
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: theme.controlRadius
                                    color: modelData.primary ? theme.accent : theme.reading
                                    border.width: 1
                                    border.color: modelData.primary ? theme.accent : theme.border

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.icon
                                        font.family: theme.fontFamily
                                        font.pixelSize: modelData.primary ? 16 : 13
                                        color: modelData.primary ? theme.base : theme.text
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.mediaAction(modelData.act)
                                    }
                                }
                            }
                        }

                        // Progress Bar
                        Item {
                            x: 10; y: 84
                            width: parent.width - 20; height: 24

                            Text {
                                id: posLabel
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                text: root.stateData.media.positionStr || "0:00"
                                font.family: theme.fontFamily; font.pixelSize: 10
                                color: theme.muted
                            }

                            Rectangle {
                                id: progTrack
                                anchors.left: posLabel.right; anchors.leftMargin: 8
                                anchors.right: lenLabel.left; anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                height: 6; radius: 3
                                color: theme.reading

                                Rectangle {
                                    width: root.stateData.media.length > 0
                                        ? Math.min(parent.width, Math.max(0, parent.width * (root.stateData.media.position / root.stateData.media.length)))
                                        : 0
                                    height: parent.height; radius: 3
                                    color: theme.accent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (mouse) => {
                                        if (root.stateData.media.length > 0) {
                                            const target = Math.round((mouse.x / width) * root.stateData.media.length);
                                            Quickshell.execDetached(["playerctl", "position", String(target)]);
                                            refreshTimer.restart();
                                        }
                                    }
                                }
                            }

                            Text {
                                id: lenLabel
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: root.stateData.media.lengthStr || "0:00"
                                font.family: theme.fontFamily; font.pixelSize: 10
                                color: theme.muted
                            }
                        }
                    }

                    // Weather & 3-Day Forecast Card
                    Rectangle {
                        width: parent.width
                        height: 160
                        radius: theme.controlRadius
                        color: theme.control
                        border.width: 1
                        border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                        // Current Weather Header
                        Item {
                            x: 12; y: 10
                            width: parent.width - 24; height: 54

                            Row {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                spacing: 10

                                Text {
                                    text: root.stateData.weather.icon || "󰖙"
                                    font.family: theme.fontFamily; font.pixelSize: 28
                                    color: theme.accent
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        text: (root.stateData.weather.tempC || "--") + "°C · " + (root.stateData.weather.condition || "Weather")
                                        font.family: theme.fontFamily; font.pixelSize: theme.fontTitle; font.bold: true
                                        color: theme.text
                                    }
                                    Text {
                                        text: (root.stateData.weather.location || "Local") + " · Feels " + (root.stateData.weather.feelsLikeC || "--") + "°C · 󰖎 " + (root.stateData.weather.humidity || "--") + "% · 󰖝 " + (root.stateData.weather.windKmph || "--") + " km/h"
                                        font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary
                                        color: theme.muted
                                    }
                                }
                            }

                            Rectangle {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                width: 28; height: 28
                                radius: theme.controlRadius
                                color: theme.reading
                                border.width: 1
                                border.color: theme.border

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰑐"
                                    font.family: theme.fontFamily; font.pixelSize: 13
                                    color: theme.accent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.refreshWeather()
                                }
                            }
                        }

                        // 3-Day Forecast Grid
                        Row {
                            x: 12; y: 72
                            width: parent.width - 24; height: 76
                            spacing: 8

                            Repeater {
                                model: (root.stateData.weather.forecast && root.stateData.weather.forecast.length > 0)
                                    ? root.stateData.weather.forecast
                                    : [
                                        { date: "Today", icon: root.stateData.weather.icon || "󰖙", condition: root.stateData.weather.condition || "Clear", maxC: root.stateData.weather.tempC || "--", minC: "--" },
                                        { date: "Day 2", icon: "󰖕", condition: "Forecast", maxC: "--", minC: "--" },
                                        { date: "Day 3", icon: "󰖐", condition: "Forecast", maxC: "--", minC: "--" }
                                    ]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: (parent.width - 16) / 3
                                    height: parent.height
                                    radius: Math.max(4, theme.controlRadius - 1)
                                    color: theme.reading
                                    border.width: 1
                                    border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.06)

                                    Column {
                                        anchors.centerIn: parent
                                        width: parent.width - 10
                                        spacing: 2

                                        Text {
                                            width: parent.width
                                            horizontalAlignment: Text.AlignHCenter
                                            text: modelData.date || "Day"
                                            font.family: theme.fontFamily; font.pixelSize: 10; font.bold: true
                                            color: theme.muted
                                        }

                                        Row {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            spacing: 6
                                            Text {
                                                text: modelData.icon || "󰖐"
                                                font.family: theme.fontFamily; font.pixelSize: 16
                                                color: theme.accent
                                            }
                                            Text {
                                                text: (modelData.maxC || "--") + "° / " + (modelData.minC || "--") + "°"
                                                font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: true
                                                color: theme.text
                                            }
                                        }

                                        Text {
                                            width: parent.width
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                            text: modelData.condition || ""
                                            font.family: theme.fontFamily; font.pixelSize: 10
                                            color: theme.muted
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
