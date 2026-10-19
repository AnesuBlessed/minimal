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
    property string activeTab: Quickshell.env("MINIMAL_CC_TAB") || "quick"
    property bool busy: false
    property string pendingSsid: ""
    property string wifiPassword: ""
    property bool showWifiPassword: false

    readonly property var tabs: [
        { id: "quick", icon: "󰒓", label: "Quick" },
        { id: "wifi", icon: "󰖩", label: "Wi-Fi" },
        { id: "bluetooth", icon: "󰂯", label: "Bluetooth" },
        { id: "audio", icon: "󰕾", label: "Audio" }
    ]

    property var stateData: ({
        wifi: { available: true, enabled: true, connectedSsid: "", ipAddress: "", interface: "", hotspotActive: false, networks: [] },
        bluetooth: { available: true, powered: false, discoverable: false, controller: "Bluetooth", devices: [] },
        audio: { volume: 50, muted: false, micVolume: 80, micMuted: false, sinks: [], sources: [] },
        system: { brightness: 80, caffeine: false, nightLight: false, dnd: false, airplane: false }
    })

    readonly property var connectedWifiNetworks: {
        var res = [];
        var nets = (root.stateData && root.stateData.wifi && root.stateData.wifi.networks) ? root.stateData.wifi.networks : [];
        for (var i = 0; i < nets.length; i++) {
            if (nets[i].inUse) res.push(nets[i]);
        }
        return res;
    }

    readonly property var availableWifiNetworks: {
        var res = [];
        var nets = (root.stateData && root.stateData.wifi && root.stateData.wifi.networks) ? root.stateData.wifi.networks : [];
        for (var i = 0; i < nets.length; i++) {
            if (!nets[i].inUse) res.push(nets[i]);
        }
        return res;
    }

    readonly property var connectedBtDevices: {
        var res = [];
        var devs = (root.stateData && root.stateData.bluetooth && root.stateData.bluetooth.devices) ? root.stateData.bluetooth.devices : [];
        for (var i = 0; i < devs.length; i++) {
            if (devs[i].connected) res.push(devs[i]);
        }
        return res;
    }

    readonly property var availableBtDevices: {
        var res = [];
        var devs = (root.stateData && root.stateData.bluetooth && root.stateData.bluetooth.devices) ? root.stateData.bluetooth.devices : [];
        for (var i = 0; i < devs.length; i++) {
            if (!devs[i].connected) res.push(devs[i]);
        }
        return res;
    }

    function applyJson(raw) {
        if (!raw || raw.trim() === "") return;
        try {
            const parsed = JSON.parse(raw);
            if (parsed && typeof parsed === "object") {
                const prevNetworks = (stateData && stateData.wifi && stateData.wifi.networks) ? stateData.wifi.networks : [];
                const newNetworks = (parsed.wifi && parsed.wifi.networks && parsed.wifi.networks.length > 0)
                    ? parsed.wifi.networks
                    : prevNetworks;
                stateData = {
                    wifi: Object.assign({ available: true, enabled: false, connectedSsid: "", ipAddress: "", interface: "", hotspotActive: false, networks: [] }, parsed.wifi || {}, { networks: newNetworks }),
                    bluetooth: Object.assign({ available: true, powered: false, discoverable: false, controller: "Bluetooth", devices: [] }, parsed.bluetooth || {}),
                    audio: Object.assign({ volume: 50, muted: false, micVolume: 80, micMuted: false, sinks: [], sources: [] }, parsed.audio || {}),
                    system: Object.assign({ brightness: 80, caffeine: false, nightLight: false, dnd: false, airplane: false }, parsed.system || {})
                };
            }
        } catch (e) {}
    }

    property var actionQueue: []

    function runAction(args) {
        if (!args || args.length === 0) return;
        if (actionProc.running) {
            actionQueue.push(args);
            return;
        }
        busy = true;
        actionProc.command = ["python3", root.minimalRoot + "/scripts/control-center-backend.py", "--action"].concat(args);
        actionProc.running = true;
    }

    Process {
        id: actionProc
        stdout: SplitParser {
            onRead: data => root.applyJson(data)
        }
        onExited: {
            root.busy = false;
            if (root.actionQueue.length > 0) {
                const nextArgs = root.actionQueue.shift();
                root.runAction(nextArgs);
            }
        }
    }

    Process {
        id: pollProc
        command: ["python3", root.minimalRoot + "/scripts/control-center-backend.py", "--state"]
        stdout: SplitParser {
            onRead: data => root.applyJson(data)
        }
    }

    Component.onCompleted: {
        applyJson(Quickshell.env("MINIMAL_CC_JSON"));
    }

    PanelWindow {
        id: panel
        screen: Quickshell.screens.find(s => s.name === Quickshell.env("MINIMAL_POPUP_OUTPUT")) || Quickshell.screens[0]
        anchors.bottom: true
        implicitWidth: Math.min(540, screen.width - 24)
        implicitHeight: Math.min(440, screen.height - 48)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "minimal-control-center"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        HyprlandFocusGrab {
            windows: [panel]
            active: true
            onCleared: Qt.quit()
        }

        Item {
            anchors.fill: parent
            focus: !passInput.activeFocus
            Keys.onEscapePressed: {
                if (root.pendingSsid !== "") {
                    root.pendingSsid = "";
                    root.wifiPassword = "";
                } else {
                    Qt.quit();
                }
            }
            Keys.onTabPressed: {
                const ids = root.tabs.map(t => t.id);
                const idx = ids.indexOf(root.activeTab);
                root.activeTab = ids[(idx + 1) % ids.length];
            }

            Rectangle {
                anchors.fill: parent
                topLeftRadius: theme.panelRadius
                topRightRadius: theme.panelRadius
                color: theme.reading
                border.width: 1
                border.color: theme.border

                // Top drag handle
                Rectangle {
                    width: 32; height: 3; radius: 1.5
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 8
                    color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.32)
                }

                // Segmented Navigation Bar
                Row {
                    id: tabBar
                    x: 12; y: 20
                    spacing: 6

                    Repeater {
                        model: root.tabs
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool active: root.activeTab === modelData.id
                            width: (panel.width - 24 - 18) / 4
                            height: 30
                            radius: theme.controlRadius
                            color: active ? theme.accent : theme.control
                            border.width: 1
                            border.color: active ? theme.accent : Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    text: modelData.icon
                                    font.family: theme.fontFamily; font.pixelSize: 13
                                    color: active ? theme.base : theme.accent
                                }
                                Text {
                                    text: modelData.label
                                    font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: active
                                    color: active ? theme.base : theme.text
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeTab = modelData.id
                            }
                        }
                    }
                }

                // =============================================================
                // TAB 1: QUICK CONTROLS
                // =============================================================
                Column {
                    visible: root.activeTab === "quick"
                    x: 12; y: 60
                    width: parent.width - 24
                    spacing: 10

                    // 2x3 Quick Toggles Grid
                    Grid {
                        columns: 3
                        spacing: 8
                        width: parent.width

                        Repeater {
                            model: [
                                {
                                    icon: root.stateData.wifi.enabled ? "󰖩" : "󰖪",
                                    title: "Wi-Fi",
                                    sub: root.stateData.wifi.connectedSsid || (root.stateData.wifi.enabled ? "On" : "Off"),
                                    active: root.stateData.wifi.enabled,
                                    act: ["wifi-toggle"],
                                    moreTab: "wifi"
                                },
                                {
                                    icon: root.stateData.bluetooth.powered ? "󰂯" : "󰂲",
                                    title: "Bluetooth",
                                    sub: root.stateData.bluetooth.powered ? "Powered On" : "Off",
                                    active: root.stateData.bluetooth.powered,
                                    act: ["bt-toggle"],
                                    moreTab: "bluetooth"
                                },
                                {
                                    icon: "󰀝",
                                    title: "Airplane",
                                    sub: root.stateData.system.airplane ? "Active" : "Off",
                                    active: root.stateData.system.airplane,
                                    act: ["airplane-toggle"],
                                    moreTab: ""
                                },
                                {
                                    icon: "󰖔",
                                    title: "Night Light",
                                    sub: root.stateData.system.nightLight ? "Warm 4200K" : "Off",
                                    active: root.stateData.system.nightLight,
                                    act: ["nightlight-toggle"],
                                    moreTab: ""
                                },
                                {
                                    icon: "󰅶",
                                    title: "Caffeine",
                                    sub: root.stateData.system.caffeine ? "Awake" : "Normal Idle",
                                    active: root.stateData.system.caffeine,
                                    act: ["caffeine-toggle"],
                                    moreTab: ""
                                },
                                {
                                    icon: "󰂛",
                                    title: "Do Not Disturb",
                                    sub: root.stateData.system.dnd ? "Silenced" : "Alerts On",
                                    active: root.stateData.system.dnd,
                                    act: ["dnd-toggle"],
                                    moreTab: ""
                                }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: (parent.width - 16) / 3
                                height: 56
                                radius: theme.controlRadius
                                color: modelData.active ? theme.accent : theme.control
                                border.width: 1
                                border.color: modelData.active ? theme.accent : Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                                Row {
                                    x: 10; anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8
                                    width: parent.width - 20

                                    Text {
                                        text: modelData.icon
                                        font.family: theme.fontFamily; font.pixelSize: 18
                                        color: modelData.active ? theme.base : theme.accent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Column {
                                        width: parent.width - 30
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 1
                                        Text {
                                            width: parent.width
                                            text: modelData.title
                                            elide: Text.ElideRight
                                            font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: true
                                            color: modelData.active ? theme.base : theme.text
                                        }
                                        Text {
                                            width: parent.width
                                            text: modelData.sub
                                            elide: Text.ElideRight
                                            font.family: theme.fontFamily; font.pixelSize: 10
                                            color: modelData.active ? Qt.rgba(theme.base.r, theme.base.g, theme.base.b, 0.78) : theme.muted
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton && modelData.moreTab !== "") {
                                            root.activeTab = modelData.moreTab;
                                        } else {
                                            if (modelData.act[0] === "wifi-toggle") {
                                                root.stateData.wifi.enabled = !root.stateData.wifi.enabled;
                                            } else if (modelData.act[0] === "bt-toggle") {
                                                root.stateData.bluetooth.powered = !root.stateData.bluetooth.powered;
                                            } else if (modelData.act[0] === "airplane-toggle") {
                                                root.stateData.system.airplane = !root.stateData.system.airplane;
                                            } else if (modelData.act[0] === "nightlight-toggle") {
                                                root.stateData.system.nightLight = !root.stateData.system.nightLight;
                                            } else if (modelData.act[0] === "caffeine-toggle") {
                                                root.stateData.system.caffeine = !root.stateData.system.caffeine;
                                            } else if (modelData.act[0] === "dnd-toggle") {
                                                root.stateData.system.dnd = !root.stateData.system.dnd;
                                            }
                                            root.runAction(modelData.act);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Sliders Card (Audio Output, Microphone, Brightness)
                    Rectangle {
                        width: parent.width
                        height: 158
                        radius: theme.controlRadius
                        color: theme.control
                        border.width: 1
                        border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                        Column {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 14

                            Repeater {
                                model: [
                                    {
                                        icon: root.stateData.audio.muted ? "󰝟" : "󰕾",
                                        label: "Speaker",
                                        val: root.stateData.audio.volume,
                                        max: 100,
                                        muteAct: ["audio-mute"],
                                        setAct: "audio-volume",
                                        setLocal: (pct) => { root.stateData.audio.volume = pct; root.stateData.audio.muted = false; },
                                        toggleMuteLocal: () => { root.stateData.audio.muted = !root.stateData.audio.muted; }
                                    },
                                    {
                                        icon: root.stateData.audio.micMuted ? "󰍭" : "󰍬",
                                        label: "Mic",
                                        val: root.stateData.audio.micVolume,
                                        max: 100,
                                        muteAct: ["mic-mute"],
                                        setAct: "mic-volume",
                                        setLocal: (pct) => { root.stateData.audio.micVolume = pct; root.stateData.audio.micMuted = false; },
                                        toggleMuteLocal: () => { root.stateData.audio.micMuted = !root.stateData.audio.micMuted; }
                                    },
                                    {
                                        icon: "󰃠",
                                        label: "Display",
                                        val: root.stateData.system.brightness,
                                        max: 100,
                                        muteAct: [],
                                        setAct: "brightness",
                                        setLocal: (pct) => { root.stateData.system.brightness = pct; },
                                        toggleMuteLocal: () => {}
                                    }
                                ]
                                delegate: Item {
                                    required property var modelData
                                    width: parent.width; height: 32

                                    Rectangle {
                                        id: iconBtn
                                        width: 30; height: 30
                                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                        radius: Math.max(4, theme.controlRadius - 1)
                                        color: theme.reading
                                        border.width: 1; border.color: theme.border

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.icon
                                            font.family: theme.fontFamily; font.pixelSize: 14
                                            color: theme.accent
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: modelData.muteAct.length ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                if (modelData.muteAct.length) {
                                                    modelData.toggleMuteLocal();
                                                    root.runAction(modelData.muteAct);
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        id: sLabel
                                        x: 38; width: 58
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.label
                                        font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                        color: theme.text
                                    }

                                    Rectangle {
                                        id: barBg
                                        anchors.left: sLabel.right; anchors.leftMargin: 6
                                        anchors.right: pctText.left; anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 10; radius: 5
                                        color: theme.reading

                                        Rectangle {
                                            width: Math.min(parent.width, Math.max(0, parent.width * (modelData.val / modelData.max)))
                                            height: parent.height; radius: 5
                                            color: theme.accent
                                        }

                                        Timer {
                                            id: dragThrottleTimer
                                            interval: 40
                                            repeat: false
                                            property int pendingPct: -1
                                            onTriggered: {
                                                if (pendingPct >= 0) {
                                                    barBg.applyHardware(pendingPct);
                                                    pendingPct = -1;
                                                }
                                            }
                                        }

                                        function applyHardware(pct) {
                                            if (modelData.setAct === "audio-volume") {
                                                Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"]);
                                                Quickshell.execDetached(["wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SINK@", pct + "%"]);
                                            } else if (modelData.setAct === "mic-volume") {
                                                Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "0"]);
                                                Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", pct + "%"]);
                                            } else if (modelData.setAct === "brightness") {
                                                Quickshell.execDetached(["brightnessctl", "--class=backlight", "set", pct + "%"]);
                                            } else {
                                                root.runAction([modelData.setAct, String(pct)]);
                                            }
                                        }

                                        function handleInput(mouseX) {
                                            const pct = Math.max(1, Math.min(100, Math.round((mouseX / barBg.width) * 100)));
                                            modelData.setLocal(pct);
                                            if (dragThrottleTimer.running) {
                                                dragThrottleTimer.pendingPct = pct;
                                            } else {
                                                applyHardware(pct);
                                                dragThrottleTimer.start();
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            preventStealing: true

                                            onPressed: (mouse) => barBg.handleInput(mouse.x)
                                            onPositionChanged: (mouse) => {
                                                if (mouse.buttons & Qt.LeftButton) {
                                                    barBg.handleInput(mouse.x);
                                                }
                                            }
                                            onReleased: (mouse) => {
                                                const pct = Math.max(1, Math.min(100, Math.round((mouse.x / barBg.width) * 100)));
                                                barBg.applyHardware(pct);
                                                dragThrottleTimer.stop();
                                            }
                                        }
                                    }

                                    Text {
                                        id: pctText
                                        width: 36
                                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignRight
                                        text: modelData.val + "%"
                                        font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary
                                        color: theme.muted
                                    }
                                }
                            }
                        }
                    }
                }

                // =============================================================
                // TAB 2: FULL WI-FI MANAGER
                // =============================================================
                Item {
                    visible: root.activeTab === "wifi"
                    x: 12; y: 60
                    width: parent.width - 24
                    height: parent.height - 72

                    // Top Wi-Fi Control Bar
                    Rectangle {
                        id: wifiHeader
                        width: parent.width; height: 42
                        radius: theme.controlRadius
                        color: theme.control
                        border.width: 1
                        border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                        Row {
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                text: root.stateData.wifi.enabled ? "󰖩" : "󰖪"
                                font.family: theme.fontFamily; font.pixelSize: 16
                                color: theme.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    text: root.stateData.wifi.connectedSsid
                                        ? ("Connected: " + root.stateData.wifi.connectedSsid)
                                        : (root.stateData.wifi.enabled ? "Wi-Fi Enabled · Disconnected" : "Wi-Fi Disabled")
                                    font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: true
                                    color: theme.text
                                }
                                Text {
                                    visible: root.stateData.wifi.ipAddress !== ""
                                    text: "IP: " + root.stateData.wifi.ipAddress + " (" + root.stateData.wifi.interface + ")"
                                    font.family: theme.fontFamily; font.pixelSize: 10
                                    color: theme.muted
                                }
                            }
                        }

                        Row {
                            anchors.right: parent.right; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            // Hotspot Toggle
                            Rectangle {
                                width: hsText.implicitWidth + 14; height: 26
                                radius: Math.max(4, theme.controlRadius - 1)
                                color: root.stateData.wifi.hotspotActive ? theme.accent : theme.reading
                                border.width: 1; border.color: theme.border
                                Text {
                                    id: hsText; anchors.centerIn: parent
                                    text: root.stateData.wifi.hotspotActive ? "󰀂 Hotspot On" : "󰀂 Hotspot"
                                    font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                    color: root.stateData.wifi.hotspotActive ? theme.base : theme.text
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runAction(["wifi-hotspot"])
                                }
                            }

                            // Scan Button
                            Rectangle {
                                width: 58; height: 26
                                radius: Math.max(4, theme.controlRadius - 1)
                                color: theme.reading
                                border.width: 1; border.color: theme.border
                                Text {
                                    anchors.centerIn: parent
                                    text: root.busy ? "…" : "󰑐 Scan"
                                    font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                    color: theme.accent
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runAction(["wifi-scan"])
                                }
                            }

                            // Radio Power Toggle
                            Rectangle {
                                width: 52; height: 26
                                radius: Math.max(4, theme.controlRadius - 1)
                                color: root.stateData.wifi.enabled ? theme.accent : theme.reading
                                border.width: 1; border.color: theme.border
                                Text {
                                    anchors.centerIn: parent
                                    text: root.stateData.wifi.enabled ? "ON" : "OFF"
                                    font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                    color: root.stateData.wifi.enabled ? theme.base : theme.muted
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runAction(["wifi-toggle"])
                                }
                            }
                        }
                    }

                    // Inline Password Prompt (when connecting to an unsaved secured SSID)
                    Rectangle {
                        id: passBox
                        visible: root.pendingSsid !== ""
                        y: 48
                        width: parent.width; height: 40
                        radius: theme.controlRadius
                        color: theme.reading
                        border.width: 1; border.color: theme.accent

                        Text {
                            id: passPrompt
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            text: "󰌾 " + root.pendingSsid + ":"
                            font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                            color: theme.accent
                        }

                        TextInput {
                            id: passInput
                            anchors.left: passPrompt.right; anchors.leftMargin: 8
                            anchors.right: passEyeBtn.left; anchors.rightMargin: 6
                            height: parent.height
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: root.showWifiPassword ? TextInput.Normal : TextInput.Password
                            font.family: theme.fontFamily; font.pixelSize: theme.fontBody
                            color: theme.text; selectionColor: theme.selection
                            clip: true
                            onTextChanged: root.wifiPassword = text
                            Keys.onReturnPressed: {
                                const target = root.pendingSsid;
                                const pw = root.wifiPassword;
                                root.pendingSsid = "";
                                root.wifiPassword = "";
                                root.showWifiPassword = false;
                                passInput.text = "";
                                root.runAction(["wifi-connect", target, pw]);
                            }
                            Keys.onEscapePressed: {
                                root.pendingSsid = "";
                                root.wifiPassword = "";
                                root.showWifiPassword = false;
                                passInput.text = "";
                            }
                        }

                        Rectangle {
                            id: passEyeBtn
                            anchors.right: passConnectBtn.left; anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26; height: 26
                            radius: Math.max(4, theme.controlRadius - 2)
                            color: passEyeArea.containsMouse ? theme.selection : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: root.showWifiPassword ? "󰈉" : "󰈈"
                                font.family: theme.fontFamily; font.pixelSize: 13
                                color: root.showWifiPassword ? theme.accent : theme.muted
                            }
                            MouseArea {
                                id: passEyeArea
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: root.showWifiPassword = !root.showWifiPassword
                            }
                        }

                        Rectangle {
                            id: passConnectBtn
                            anchors.right: parent.right; anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 68; height: 26
                            radius: Math.max(4, theme.controlRadius - 1)
                            color: theme.accent
                            Text {
                                anchors.centerIn: parent; text: "Join"
                                font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                color: theme.base
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const target = root.pendingSsid;
                                    const pw = root.wifiPassword;
                                    root.pendingSsid = "";
                                    root.wifiPassword = "";
                                    root.showWifiPassword = false;
                                    passInput.text = "";
                                    root.runAction(["wifi-connect", target, pw]);
                                }
                            }
                        }
                    }

                    // Wi-Fi Network List
                    Component {
                        id: wifiCardDelegate

                        Rectangle {
                            required property var modelData
                            width: wifiCol.width; height: 42
                            radius: theme.controlRadius
                            color: modelData.inUse ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.16) : theme.control
                            border.width: 1
                            border.color: modelData.inUse ? theme.accent : Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.06)

                            Row {
                                x: 10; anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                width: parent.width - 150

                                Text {
                                    text: modelData.signal >= 75 ? "󰤨" : (modelData.signal >= 50 ? "󰤥" : (modelData.signal >= 25 ? "󰤢" : "󰤟"))
                                    font.family: theme.fontFamily; font.pixelSize: 15
                                    color: modelData.inUse ? theme.accent : theme.text
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    width: parent.width - 30
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        width: parent.width
                                        text: modelData.ssid
                                        elide: Text.ElideRight
                                        font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: modelData.inUse
                                        color: theme.text
                                    }
                                    Text {
                                        text: modelData.signal + "% · " + modelData.security + (modelData.inUse ? " · Connected" : (modelData.saved ? " · Saved" : ""))
                                        font.family: theme.fontFamily; font.pixelSize: 10
                                        color: modelData.inUse ? theme.accent : theme.muted
                                    }
                                }
                            }

                            Row {
                                anchors.right: parent.right; anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                // Connect / Disconnect button
                                Rectangle {
                                    width: 78; height: 26
                                    radius: Math.max(4, theme.controlRadius - 1)
                                    color: modelData.inUse ? theme.reading : theme.accent
                                    border.width: 1; border.color: theme.border
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.inUse ? "Disconnect" : "Connect"
                                        font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                        color: modelData.inUse ? theme.text : theme.base
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (modelData.inUse) {
                                                root.runAction(["wifi-disconnect", modelData.ssid]);
                                            } else if (modelData.saved || !modelData.secured) {
                                                root.runAction(["wifi-connect", modelData.ssid]);
                                            } else {
                                                root.pendingSsid = modelData.ssid;
                                                root.wifiPassword = "";
                                                passInput.text = "";
                                                passInput.forceActiveFocus();
                                            }
                                        }
                                    }
                                }

                                // Forget saved profile button
                                Rectangle {
                                    visible: modelData.saved
                                    width: 28; height: 26
                                    radius: Math.max(4, theme.controlRadius - 1)
                                    color: theme.reading
                                    border.width: 1; border.color: theme.border
                                    Text {
                                        anchors.centerIn: parent; text: "󰆴"
                                        font.family: theme.fontFamily; font.pixelSize: 13
                                        color: theme.muted
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.runAction(["wifi-forget", modelData.ssid])
                                    }
                                }
                            }
                        }
                    }

                    Flickable {
                        id: wifiFlick
                        y: passBox.visible ? 94 : 48
                        width: parent.width; height: parent.height - y
                        contentWidth: width
                        contentHeight: wifiCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { width: 3; policy: ScrollBar.AsNeeded }

                        Column {
                            id: wifiCol
                            width: parent.width
                            spacing: 6

                            Text {
                                visible: root.connectedWifiNetworks.length > 0
                                width: parent.width
                                text: "CONNECTED"
                                color: theme.accent
                                font.family: theme.fontFamily; font.pixelSize: 10; font.bold: true
                            }

                            Repeater {
                                model: root.connectedWifiNetworks
                                delegate: wifiCardDelegate
                            }

                            Item {
                                visible: root.connectedWifiNetworks.length > 0 && root.availableWifiNetworks.length > 0
                                width: parent.width; height: 4
                            }

                            Text {
                                visible: root.availableWifiNetworks.length > 0
                                width: parent.width
                                text: "AVAILABLE NETWORKS"
                                color: theme.muted
                                font.family: theme.fontFamily; font.pixelSize: 10; font.bold: true
                            }

                            Repeater {
                                model: root.availableWifiNetworks
                                delegate: wifiCardDelegate
                            }

                            Text {
                                visible: root.stateData.wifi.enabled && root.connectedWifiNetworks.length === 0 && root.availableWifiNetworks.length === 0
                                width: parent.width
                                text: "No Wi-Fi networks found"
                                font.family: theme.fontFamily; font.pixelSize: theme.fontBody
                                color: theme.muted
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }

                // =============================================================
                // TAB 3: FULL BLUETOOTH MANAGER
                // =============================================================
                Item {
                    visible: root.activeTab === "bluetooth"
                    x: 12; y: 60
                    width: parent.width - 24
                    height: parent.height - 72

                    Rectangle {
                        width: parent.width; height: 42
                        radius: theme.controlRadius
                        color: theme.control
                        border.width: 1
                        border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                        Row {
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                text: root.stateData.bluetooth.powered ? "󰂯" : "󰂲"
                                font.family: theme.fontFamily; font.pixelSize: 16
                                color: theme.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    text: {
                                        var cName = root.stateData.bluetooth.name || root.stateData.bluetooth.controller || "Bluetooth";
                                        var cAddr = root.stateData.bluetooth.address || "";
                                        return cName + (cAddr ? (" · " + cAddr) : "") + (root.stateData.bluetooth.powered ? " · Powered" : " · Off");
                                    }
                                    font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: true
                                    color: theme.text
                                }
                                Text {
                                    text: root.stateData.bluetooth.discoverable ? "Always visible to nearby devices" : "Hidden from discovery"
                                    font.family: theme.fontFamily; font.pixelSize: 10
                                    color: theme.muted
                                }
                            }
                        }

                        Row {
                            anchors.right: parent.right; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Rectangle {
                                width: 92; height: 26
                                radius: Math.max(4, theme.controlRadius - 1)
                                color: root.stateData.bluetooth.discoverable ? theme.accent : theme.reading
                                border.width: 1; border.color: theme.border
                                Text {
                                    anchors.centerIn: parent
                                    text: root.stateData.bluetooth.discoverable ? "Discoverable" : "Hidden"
                                    font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                    color: root.stateData.bluetooth.discoverable ? theme.base : theme.text
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runAction(["bt-discoverable"])
                                }
                            }

                            Rectangle {
                                width: 58; height: 26
                                radius: Math.max(4, theme.controlRadius - 1)
                                color: theme.reading
                                border.width: 1; border.color: theme.border
                                Text {
                                    anchors.centerIn: parent
                                    text: root.busy ? "…" : "󰑐 Scan"
                                    font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                    color: theme.accent
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runAction(["bt-scan"])
                                }
                            }

                            Rectangle {
                                width: 52; height: 26
                                radius: Math.max(4, theme.controlRadius - 1)
                                color: root.stateData.bluetooth.powered ? theme.accent : theme.reading
                                border.width: 1; border.color: theme.border
                                Text {
                                    anchors.centerIn: parent
                                    text: root.stateData.bluetooth.powered ? "ON" : "OFF"
                                    font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                    color: root.stateData.bluetooth.powered ? theme.base : theme.muted
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runAction(["bt-toggle"])
                                }
                            }
                        }
                    }

                    Component {
                        id: btCardDelegate

                        Rectangle {
                            required property var modelData
                            width: btCol.width; height: 42
                            radius: theme.controlRadius
                            color: modelData.connected ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.16) : theme.control
                            border.width: 1
                            border.color: modelData.connected ? theme.accent : Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.06)

                            Row {
                                x: 10; anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                width: parent.width - 175

                                Text {
                                    text: modelData.connected ? "󰂱" : "󰂯"
                                    font.family: theme.fontFamily; font.pixelSize: 15
                                    color: modelData.connected ? theme.accent : theme.text
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    width: parent.width - 30
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        width: parent.width
                                        text: {
                                            var candidate = (modelData.name || "").trim();
                                            var isCode = !candidate ||
                                                         /^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/.test(candidate) ||
                                                         /^dev_[0-9A-Za-z_]+$/.test(candidate) ||
                                                         /^[0-9A-Fa-f]{12}$/.test(candidate);
                                            return isCode ? "Bluetooth Device" : candidate;
                                        }
                                        elide: Text.ElideRight
                                        font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: modelData.connected
                                        color: theme.text
                                    }
                                    Text {
                                        text: (modelData.connected ? "Connected" : (modelData.paired ? "Paired" : "Available"))
                                            + (modelData.trusted ? " · Trusted" : "")
                                            + (modelData.battery ? (" · 󰁹 " + modelData.battery) : "")
                                        font.family: theme.fontFamily; font.pixelSize: 10
                                        color: modelData.connected ? theme.accent : theme.muted
                                    }
                                }
                            }

                            Row {
                                anchors.right: parent.right; anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Rectangle {
                                    width: 78; height: 26
                                    radius: Math.max(4, theme.controlRadius - 1)
                                    color: modelData.connected ? theme.reading : theme.accent
                                    border.width: 1; border.color: theme.border
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.connected ? "Disconnect" : (modelData.paired ? "Connect" : "Pair")
                                        font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                        color: modelData.connected ? theme.text : theme.base
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.runAction([modelData.connected ? "bt-disconnect" : "bt-connect", modelData.mac])
                                    }
                                }

                                Rectangle {
                                    visible: modelData.paired || modelData.connected
                                    width: 28; height: 26
                                    radius: Math.max(4, theme.controlRadius - 1)
                                    color: theme.reading
                                    border.width: 1; border.color: theme.border
                                    Text {
                                        anchors.centerIn: parent; text: "󰈔"
                                        font.family: theme.fontFamily; font.pixelSize: 13
                                        color: theme.accent
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.runAction(["bt-send", modelData.mac])
                                    }
                                }

                                Rectangle {
                                    width: 28; height: 26
                                    radius: Math.max(4, theme.controlRadius - 1)
                                    color: modelData.trusted ? theme.accent : theme.reading
                                    border.width: 1; border.color: theme.border
                                    Text {
                                        anchors.centerIn: parent; text: "󰒃"
                                        font.family: theme.fontFamily; font.pixelSize: 13
                                        color: modelData.trusted ? theme.base : theme.muted
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.runAction(["bt-trust", modelData.mac])
                                    }
                                }

                                Rectangle {
                                    visible: modelData.paired
                                    width: 28; height: 26
                                    radius: Math.max(4, theme.controlRadius - 1)
                                    color: theme.reading
                                    border.width: 1; border.color: theme.border
                                    Text {
                                        anchors.centerIn: parent; text: "󰆴"
                                        font.family: theme.fontFamily; font.pixelSize: 13
                                        color: theme.muted
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.runAction(["bt-forget", modelData.mac])
                                    }
                                }
                            }
                        }
                    }

                    Flickable {
                        id: btFlick
                        y: 48
                        width: parent.width; height: parent.height - 48
                        contentWidth: width
                        contentHeight: btCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { width: 3; policy: ScrollBar.AsNeeded }

                        Column {
                            id: btCol
                            width: parent.width
                            spacing: 6

                            Text {
                                visible: root.connectedBtDevices.length > 0
                                width: parent.width
                                text: "CONNECTED DEVICES"
                                color: theme.accent
                                font.family: theme.fontFamily; font.pixelSize: 10; font.bold: true
                            }

                            Repeater {
                                model: root.connectedBtDevices
                                delegate: btCardDelegate
                            }

                            Item {
                                visible: root.connectedBtDevices.length > 0 && root.availableBtDevices.length > 0
                                width: parent.width; height: 4
                            }

                            Text {
                                visible: root.availableBtDevices.length > 0
                                width: parent.width
                                text: "AVAILABLE DEVICES"
                                color: theme.muted
                                font.family: theme.fontFamily; font.pixelSize: 10; font.bold: true
                            }

                            Repeater {
                                model: root.availableBtDevices
                                delegate: btCardDelegate
                            }

                            Text {
                                visible: root.stateData.bluetooth.powered && root.connectedBtDevices.length === 0 && root.availableBtDevices.length === 0
                                width: parent.width
                                text: "No Bluetooth devices found"
                                font.family: theme.fontFamily; font.pixelSize: theme.fontBody
                                color: theme.muted
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }

                // =============================================================
                // TAB 4: PIPEWIRE AUDIO OUTPUT & INPUT ROUTING
                // =============================================================
                Column {
                    visible: root.activeTab === "audio"
                    x: 12; y: 60
                    width: parent.width - 24
                    spacing: 10

                    Text {
                        text: "Output Sinks (" + root.stateData.audio.volume + "%)"
                        font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: true
                        color: theme.accent
                    }

                    Repeater {
                        model: root.stateData.audio.sinks
                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width; height: 36
                            radius: theme.controlRadius
                            color: modelData.active ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.18) : theme.control
                            border.width: 1
                            border.color: modelData.active ? theme.accent : Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                            Text {
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24
                                elide: Text.ElideRight
                                text: (modelData.active ? "󰄬  " : "󰕾  ") + modelData.name
                                font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: modelData.active
                                color: theme.text
                            }

                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: root.runAction(["audio-set-sink", modelData.id])
                            }
                        }
                    }

                    Text {
                        text: "Input Microphones (" + root.stateData.audio.micVolume + "%)"
                        font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: true
                        color: theme.accent
                    }

                    Repeater {
                        model: root.stateData.audio.sources
                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width; height: 36
                            radius: theme.controlRadius
                            color: modelData.active ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.18) : theme.control
                            border.width: 1
                            border.color: modelData.active ? theme.accent : Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                            Text {
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24
                                elide: Text.ElideRight
                                text: (modelData.active ? "󰄬  " : "󰍬  ") + modelData.name
                                font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: modelData.active
                                color: theme.text
                            }

                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: root.runAction(["audio-set-source", modelData.id])
                            }
                        }
                    }
                }
            }
        }
    }
}
