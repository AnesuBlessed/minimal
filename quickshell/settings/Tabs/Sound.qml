import QtQuick
import Quickshell
import QtQuick.Controls
import Quickshell.Services.Pipewire
import Quickshell.Io
import "../"

Item {
    id: page

    property real marginLeft: 0
    property real marginRight: 12
    property real marginTop: 0
    property real marginBottom: 0
    property real sliderMarginRight: 10
    property real sectionSpacing: 6

    PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    property var sink: Pipewire.defaultAudioSink
    property real volume: (sink && sink.audio) ? sink.audio.volume : 0
    property bool muted: (sink && sink.audio) ? sink.audio.muted : false

    property var source: Pipewire.defaultAudioSource
    property real inputVolume: (source && source.audio) ? source.audio.volume : 0
    property bool inputMuted: (source && source.audio) ? source.audio.muted : false

    property var outputSinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    property var inputSources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio)
    property var appStreams: Pipewire.nodes.values.filter(n => n.isStream && n.isSink && n.audio)

    property string activeAlsaPort: "analog-output-speaker"
    property bool headphoneAvailable: false
    property var sinkFriendlyNames: ({})
    property var btFriendlyNames: ({})

    Process {
        id: pChime
        command: ["canberra-gtk-play", "-i", "audio-volume-change"]
    }

    Process {
        id: pPorts
        command: ["python3", Quickshell.shellDir + "/../../scripts/audio-info.py", page.sink?.name || ""]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text.trim());
                    page.activeAlsaPort = data.active_port || "";
                    page.headphoneAvailable = Boolean(data.headphone_available);
                    if (data.sink_names) page.sinkFriendlyNames = data.sink_names;
                    if (data.bt_devices) page.btFriendlyNames = data.bt_devices;
                } catch (e) {
                }
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
        if (!page.sink || pSetPort.running) return;
        pSetPort.command = ["pactl", "set-sink-port", page.sink.name, portId];
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
        if (!node) return fallback;
        var name = node.name || "";
        var desc = node.description || node.nickname || "";

        if (page.sinkFriendlyNames && page.sinkFriendlyNames[name]) {
            return page.sinkFriendlyNames[name];
        }

        if (name.indexOf("bluez") !== -1 || desc.indexOf("bluez") !== -1) {
            var macMatch = name.match(/([0-9A-Fa-f]{2}[_:][0-9A-Fa-f]{2}[_:][0-9A-Fa-f]{2}[_:][0-9A-Fa-f]{2}[_:][0-9A-Fa-f]{2}[_:][0-9A-Fa-f]{2})/);
            if (macMatch && page.btFriendlyNames) {
                var macKey = macMatch[1].toUpperCase().replace(/-/g, ":").replace(/_/g, ":");
                if (page.btFriendlyNames[macKey]) return page.btFriendlyNames[macKey];
            }
            if (desc && desc.indexOf("bluez") === -1 && !/^[0-9A-Fa-f_:-]{12,}$/.test(desc)) {
                return desc;
            }
            return "Bluetooth Audio";
        }

        if (desc.indexOf("Built-in Audio") !== -1 || desc.indexOf("Analog Stereo") !== -1 || desc.indexOf("ALC3226") !== -1 || name.indexOf("analog-stereo") !== -1) {
            return "Internal Audio";
        }

        return desc || name || fallback;
    }

    readonly property var outputDevices: {
        var list = [];
        var sinks = page.outputSinks;
        if (!sinks) return list;
        for (var i = 0; i < sinks.length; i++) {
            var s = sinks[i];
            var sName = s.name || "";
            var isAlsa = (sName.indexOf("analog-stereo") !== -1 || sName.indexOf("pci-") !== -1);
            if (isAlsa) {
                var isSpeakerActive = (page.sink && page.sink.id === s.id && page.activeAlsaPort !== "analog-output-headphones");
                list.push({
                    "id": "internal-speaker",
                    "label": "Built-in Speakers",
                    "icon": "󰓃",
                    "active": isSpeakerActive,
                    "sink": s,
                    "port": "analog-output-speaker"
                });
                if (page.headphoneAvailable || page.activeAlsaPort === "analog-output-headphones") {
                    var isHpActive = (page.sink && page.sink.id === s.id && page.activeAlsaPort === "analog-output-headphones");
                    list.push({
                        "id": "internal-headphones",
                        "label": "Headphones (3.5mm)",
                        "icon": "󰋋",
                        "active": isHpActive,
                        "sink": s,
                        "port": "analog-output-headphones"
                    });
                }
            } else {
                var isBt = (sName.indexOf("bluez") !== -1);
                var isDevActive = (page.sink && page.sink.id === s.id);
                list.push({
                    "id": "sink-" + s.id,
                    "label": page.displayName(s, "Audio Output"),
                    "icon": isBt ? "󰋋" : "󰓃",
                    "active": isDevActive,
                    "sink": s,
                    "port": ""
                });
            }
        }
        return list;
    }

    function selectOutputDevice(dev) {
        if (!dev) return;
        if (dev.sink) {
            Pipewire.preferredDefaultAudioSink = dev.sink;
        }
        if (dev.port) {
            page.setSinkPort(dev.port);
        } else {
            pPorts.running = true;
        }
        if (!pChime.running) pChime.running = true;
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

        ScrollBar.vertical: SettingsScrollBar {}

        Column {
            id: content
            width: Math.max(0, flick.width - 10)
            spacing: 14

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

                    ControlArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (page.sink && page.sink.audio)
                                page.sink.audio.muted = !page.sink.audio.muted;
                        }
                    }
                }

                Slider {
                    width: outputRow.width - 42
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Output"
                    icon: ""
                    displayText: Math.round(page.volume * 100) + "%"
                    value: page.muted ? 0 : page.volume

                    onMoved: v => {
                        if (page.sink && page.sink.audio) {
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
                    model: page.outputDevices

                    delegate: Rectangle {
                        required property var modelData
                        property var outputItem: modelData
                        property bool active: Boolean(outputItem.active)

                        width: parent.width
                        height: 38
                        radius: Theme.radius
                        color: active ? Theme.alpha(Theme.accent, 0.10) : "transparent"
                        border.width: 1
                        border.color: active ? Theme.borderAccent : Theme.border

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
                                    text: outputItem.icon
                                    color: active ? Theme.accent : Theme.textFaint
                                    font.family: Theme.iconFont
                                    font.pixelSize: 14
                                }

                                Text {
                                    width: parent.width - 28
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: outputItem.label
                                    color: active ? Theme.accent : Theme.text
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fontSecondary
                                    font.bold: active
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                id: outActiveText
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: active ? "Active" : ""
                                color: Theme.accent
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fontSecondary
                                font.bold: true
                            }
                        }

                        ControlArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.selectOutputDevice(outputItem)
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

                    ControlArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (page.source && page.source.audio)
                                page.source.audio.muted = !page.source.audio.muted;
                        }
                    }
                }

                Slider {
                    width: inputRow.width - 42
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Input"
                    icon: ""
                    displayText: Math.round(page.inputVolume * 100) + "%"
                    value: page.inputMuted ? 0 : page.inputVolume

                    onMoved: v => {
                        const audio = (page.source && page.source.audio) ? page.source.audio : null;
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
                        property bool active: (page.source && input) ? (page.source.id === input.id) : false

                        width: parent.width
                        height: 38
                        radius: Theme.radius
                        color: active ? Theme.alpha(Theme.accent, 0.10) : "transparent"
                        border.width: 1
                        border.color: active ? Theme.borderAccent : Theme.border

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
                                    text: page.displayName(input, "Audio Input")
                                    color: active ? Theme.accent : Theme.text
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fontSecondary
                                    font.bold: active
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                id: inActiveText
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: active ? "Active" : ""
                                color: Theme.accent
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fontSecondary
                                font.bold: true
                            }
                        }

                        ControlArea {
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
                    text: "Per-app volume"
                    color: Theme.text
                    font.family: Theme.monoFont
                    font.pixelSize: 13
                    font.letterSpacing: 0
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "(" + page.appStreams.length + ")"
                    color: Theme.textDim
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fontSecondary
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
                        property bool streamMuted: (stream && stream.audio) ? stream.audio.muted : false
                        property real streamVolume: (stream && stream.audio) ? stream.audio.volume : 0

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

                                ControlArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (stream && stream.audio)
                                            stream.audio.muted = !stream.audio.muted;
                                    }
                                }
                            }

                            Text {
                                width: 90
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.displayName(stream, "App")
                                color: streamMuted ? Theme.textDim : Theme.text
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fontSecondary
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
                                    if (stream && stream.audio) {
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
                    text: "No active sound streams"
                    color: Theme.textDim
                    leftPadding: 4
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fontSecondary
                    font.letterSpacing: 0
                }
            }
        }
    }
}