import QtQuick
import QtQuick.Controls
import Quickshell.Services.Pipewire
import Quickshell.Io
import "../"

Item {
    id: page

    property real marginLeft: 0
    property real marginRight: 45
    property real marginTop: 0
    property real marginBottom: 0
    property real sliderMarginRight: 10
    property real sectionSpacing: 6

    PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    property var sink: Pipewire.defaultAudioSink
    property real volume: sink?.audio?.volume ?? 0
    property bool muted: sink?.audio?.muted ?? false

    property var source: Pipewire.defaultAudioSource
    property real inputVolume: source?.audio?.volume ?? 0
    property bool inputMuted: source?.audio?.muted ?? false

    property var outputSinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    property var inputSources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio)
    property var appStreams: Pipewire.nodes.values.filter(n => n.isStream && n.isSink && n.audio)

    property var alsaPorts: []
    property string activeAlsaPort: ""

    Process {
        id: pChime
        command: ["canberra-gtk-play", "-i", "audio-volume-change"]
    }

    Process {
        id: pPorts
        command: ["sh", "-c", "pactl list sinks | awk '/Ports:/{p=1;next}/Active Port:/{print \"ACTIVE:\" $3; p=0} p{print}'"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().split("\n");
                var ports = [];
                var active = "";
                for (var i = 0; i < lines.length; i++) {
                    var l = lines[i].trim();
                    if (l.indexOf("ACTIVE:") === 0) {
                        active = l.substring(7).trim();
                    } else if (l.indexOf("analog-output-speaker") === 0) {
                        ports.push({ "id": "analog-output-speaker", "label": "Speakers", "icon": "󰓃" });
                    } else if (l.indexOf("analog-output-headphones") === 0) {
                        ports.push({ "id": "analog-output-headphones", "label": "Headphones (3.5mm)", "icon": "󰋋" });
                    }
                }
                page.alsaPorts = ports;
                page.activeAlsaPort = active;
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            if (!pPorts.running) pPorts.running = true;
        }
    }

    function setSinkPort(portId) {
        page.activeAlsaPort = portId;
        pSetPort.command = ["pactl", "set-sink-port", "@DEFAULT_SINK@", portId];
        pSetPort.running = true;
    }

    Process {
        id: pSetPort
        onExited: {
            pPorts.running = true;
            if (!pChime.running) pChime.running = true;
        }
    }

    function displayName(node, fallback) {
        var raw = node?.description || node?.nickname || node?.name || fallback;
        if (raw.indexOf("Built-in Audio") !== -1 || raw.indexOf("Analog Stereo") !== -1 || raw.indexOf("ALC3226") !== -1) {
            return "Internal Audio";
        }
        if (raw.indexOf("bluez") !== -1 || (node?.name && node.name.indexOf("bluez") !== -1)) {
            return "󰂯 " + raw;
        }
        return raw;
    }

    function setDefaultOutput(output) {
        if (output) {
            Pipewire.preferredDefaultAudioSink = output;
            pPorts.running = true;
        }
    }

    function setDefaultInput(input) {
        if (input)
            Pipewire.preferredDefaultAudioSource = input;
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

        ScrollBar.vertical: ScrollBar {
            id: scrollBar
            policy: ScrollBar.AsNeeded
            width: 6

            background: Rectangle {
                color: "transparent"
                radius: width / 2
            }

            contentItem: Rectangle {
                color: Theme.accent
                radius: width / 2
            }
        }

        Column {
            id: content
            width: flick.width
            spacing: 14

            Text {
                text: "SOUND"
                color: Theme.text
                font.family: Theme.monoFont
                font.pixelSize: 19
                font.letterSpacing: 3
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }

            // Output Volume Row
            Row {
                id: outputRow
                width: parent.width
                spacing: 8

                Rectangle {
                    width: 34
                    height: 34
                    radius: Theme.radius
                    anchors.verticalCenter: parent.verticalCenter
                    color: page.muted ? Theme.alpha(Theme.danger, 0.15) : Theme.alpha(Theme.accent, 0.10)
                    border.width: 1
                    border.color: page.muted ? Theme.danger : Theme.border

                    Text {
                        anchors.centerIn: parent
                        text: page.muted ? "󰝟" : (page.volume > 0.5 ? "󰕾" : (page.volume > 0 ? "󰖀" : "󰕿"))
                        color: page.muted ? Theme.danger : Theme.accent
                        font.family: Theme.iconFont
                        font.pixelSize: 15
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (page.sink?.audio)
                                page.sink.audio.muted = !page.sink.audio.muted;
                        }
                    }
                }

                Slider {
                    width: outputRow.width - 42
                    anchors.verticalCenter: parent.verticalCenter
                    label: "OUTPUT"
                    icon: ""
                    displayText: Math.round(page.volume * 100) + "%"
                    value: page.muted ? 0 : page.volume

                    onMoved: v => {
                        if (page.sink?.audio) {
                            page.sink.audio.muted = false;
                            page.sink.audio.volume = v;
                        }
                    }

                    onCommitted: v => {
                        if (!pChime.running) pChime.running = true;
                    }
                }
            }

            // Output Sink Devices
            Column {
                width: parent.width
                spacing: page.sectionSpacing

                Repeater {
                    model: page.outputSinks

                    delegate: Rectangle {
                        required property var modelData
                        property var output: modelData
                        property bool active: page.sink?.id === output?.id

                        width: parent.width
                        height: 38
                        radius: Theme.radius
                        color: active ? Theme.alpha(Theme.accent, 0.10) : "transparent"
                        border.width: 1
                        border.color: active ? Theme.accent : Theme.border

                        Item {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12

                            Row {
                                anchors.left: parent.left
                                anchors.right: outActiveText.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10

                                Text {
                                    width: 18
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: active ? "󰓃" : "󰓄"
                                    color: active ? Theme.accent : Theme.textFaint
                                    font.family: Theme.iconFont
                                    font.pixelSize: 14
                                }

                                Text {
                                    width: parent.width - 28
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: page.displayName(output, "Audio Output").toUpperCase()
                                    color: active ? Theme.accent : Theme.text
                                    font.family: Theme.monoFont
                                    font.pixelSize: 11
                                    font.bold: active
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                id: outActiveText
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: active ? "ACTIVE" : ""
                                color: Theme.accent
                                font.family: Theme.monoFont
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.setDefaultOutput(output)
                        }
                    }
                }
            }

            // Earphones & Speakers Port Switcher (for ALSA / 3.5mm jack)
            Row {
                width: parent.width
                spacing: 8
                visible: page.alsaPorts.length > 0

                Repeater {
                    model: page.alsaPorts

                    delegate: Rectangle {
                        required property var modelData
                        property bool active: page.activeAlsaPort === modelData.id
                        width: (parent.width - 8) / 2
                        height: 36
                        radius: Theme.radiusSm
                        color: active ? Theme.alpha(Theme.accent, 0.15) : Theme.tint("#ffffff", 0.04)
                        border.width: 1
                        border.color: active ? Theme.accent : Theme.border

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: modelData.icon
                                color: active ? Theme.accent : Theme.textDim
                                font.family: Theme.iconFont
                                font.pixelSize: 14
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: modelData.label.toUpperCase()
                                color: active ? Theme.accent : Theme.text
                                font.family: Theme.monoFont
                                font.pixelSize: 10
                                font.bold: true
                                font.letterSpacing: 0.8
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.setSinkPort(modelData.id)
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }

            // Input (Microphone) Row
            Row {
                id: inputRow
                width: parent.width
                spacing: 8

                Rectangle {
                    width: 34
                    height: 34
                    radius: Theme.radius
                    anchors.verticalCenter: parent.verticalCenter
                    color: page.inputMuted ? Theme.alpha(Theme.danger, 0.15) : Theme.alpha(Theme.accent, 0.10)
                    border.width: 1
                    border.color: page.inputMuted ? Theme.danger : Theme.border

                    Text {
                        anchors.centerIn: parent
                        text: page.inputMuted ? "󰍭" : "󰍬"
                        color: page.inputMuted ? Theme.danger : Theme.accent
                        font.family: Theme.iconFont
                        font.pixelSize: 15
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (page.source?.audio)
                                page.source.audio.muted = !page.source.audio.muted;
                        }
                    }
                }

                Slider {
                    width: inputRow.width - 42
                    anchors.verticalCenter: parent.verticalCenter
                    label: "INPUT"
                    icon: ""
                    displayText: Math.round(page.inputVolume * 100) + "%"
                    value: page.inputMuted ? 0 : page.inputVolume

                    onMoved: v => {
                        const audio = page.source?.audio;
                        if (!audio) return;
                        audio.muted = false;
                        audio.volume = v;
                    }
                }
            }

            // Input Sources
            Column {
                width: parent.width
                spacing: page.sectionSpacing

                Repeater {
                    model: page.inputSources

                    delegate: Rectangle {
                        required property var modelData
                        property var input: modelData
                        property bool active: page.source?.id === input?.id

                        width: parent.width
                        height: 38
                        radius: Theme.radius
                        color: active ? Theme.alpha(Theme.accent, 0.10) : "transparent"
                        border.width: 1
                        border.color: active ? Theme.accent : Theme.border

                        Item {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12

                            Row {
                                anchors.left: parent.left
                                anchors.right: inActiveText.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10

                                Text {
                                    width: 18
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: active ? "󰍬" : "󰍭"
                                    color: active ? Theme.accent : Theme.textFaint
                                    font.family: Theme.iconFont
                                    font.pixelSize: 14
                                }

                                Text {
                                    width: parent.width - 28
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: page.displayName(input, "Audio Input").toUpperCase()
                                    color: active ? Theme.accent : Theme.text
                                    font.family: Theme.monoFont
                                    font.pixelSize: 11
                                    font.bold: active
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                id: inActiveText
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: active ? "ACTIVE" : ""
                                color: Theme.accent
                                font.family: Theme.monoFont
                                font.pixelSize: 9
                                font.bold: true
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.setDefaultInput(input)
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }

            // Per-App Volume Header
            Row {
                width: parent.width
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "PER-APP VOLUME"
                    color: Theme.text
                    font.family: Theme.monoFont
                    font.pixelSize: 13
                    font.letterSpacing: 2
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "(" + page.appStreams.length + ")"
                    color: Theme.textDim
                    font.family: Theme.monoFont
                    font.pixelSize: 11
                }
            }

            // Per-App Streams
            Column {
                width: parent.width
                spacing: page.sectionSpacing

                Repeater {
                    model: page.appStreams

                    delegate: Rectangle {
                        id: appCard

                        required property var modelData
                        property var stream: modelData
                        property bool streamMuted: stream?.audio?.muted ?? false
                        property real streamVolume: stream?.audio?.volume ?? 0

                        width: parent.width
                        height: 44
                        radius: Theme.radius
                        color: streamMuted ? Theme.alpha(Theme.danger, 0.06) : Theme.tint("#ffffff", 0.03)
                        border.width: 1
                        border.color: streamMuted ? Theme.alpha(Theme.danger, 0.5) : Theme.border

                        Row {
                            id: appRow
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Rectangle {
                                width: 28
                                height: 28
                                radius: Theme.radius
                                anchors.verticalCenter: parent.verticalCenter
                                color: streamMuted ? Theme.alpha(Theme.danger, 0.15) : Theme.alpha(Theme.accent, 0.10)
                                border.width: 1
                                border.color: streamMuted ? Theme.danger : Theme.border

                                Text {
                                    anchors.centerIn: parent
                                    text: streamMuted ? "󰝟" : "󰕾"
                                    color: streamMuted ? Theme.danger : Theme.accent
                                    font.family: Theme.iconFont
                                    font.pixelSize: 12
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (stream?.audio)
                                            stream.audio.muted = !stream.audio.muted;
                                    }
                                }
                            }

                            Text {
                                width: 90
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.displayName(stream, "App").toUpperCase()
                                color: streamMuted ? Theme.textDim : Theme.text
                                font.family: Theme.monoFont
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }

                            Slider {
                                width: appRow.width - 28 - 90 - 24
                                anchors.verticalCenter: parent.verticalCenter
                                label: ""
                                icon: ""
                                displayText: Math.round(streamVolume * 100) + "%"
                                value: streamMuted ? 0 : streamVolume

                                onMoved: v => {
                                    if (stream?.audio) {
                                        stream.audio.muted = false;
                                        stream.audio.volume = v;
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: page.appStreams.length === 0
                    text: "NO ACTIVE SOUND STREAMS"
                    color: Theme.textDim
                    leftPadding: 4
                    font.family: Theme.monoFont
                    font.pixelSize: 10
                    font.letterSpacing: 1.5
                }
            }
        }
    }
}