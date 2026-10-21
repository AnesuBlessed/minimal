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
    property string connectingWifiSsid: ""
    property string wifiSearchText: ""
    property string wifiError: ""
    property string lastActionError: ""
    property string connectingBtMac: ""
    property string connectingBtAction: ""

    readonly property var tabs: [
        { id: "quick", icon: "󰒓", label: "Quick" },
        { id: "wifi", icon: "󰖩", label: "Wi-Fi" },
        { id: "bluetooth", icon: "󰂯", label: "Bluetooth" },
        { id: "audio", icon: "󰕾", label: "Audio" }
    ]

    // Reactive UI state properties (direct binding for instant click responsiveness)
    property bool wifiEnabled: true
    property string wifiConnectedSsid: ""
    property bool btPowered: false
    property bool btDiscoverable: false
    property bool sysAirplane: false
    property bool sysNightLight: false
    property bool sysCaffeine: false
    property bool sysDnd: false
    property int audioVolume: 50
    property bool audioMuted: false
    property int micVolume: 80
    property bool micMuted: false
    property int sysBrightness: 80

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
        var filter = (root.wifiSearchText || "").trim().toLowerCase();
        for (var i = 0; i < nets.length; i++) {
            if (!nets[i].inUse) {
                if (!filter || (nets[i].ssid && nets[i].ssid.toLowerCase().indexOf(filter) !== -1)) {
                    res.push(nets[i]);
                }
            }
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
                if (parsed.wifi) {
                    root.wifiEnabled = !!parsed.wifi.enabled;
                    root.wifiConnectedSsid = parsed.wifi.connectedSsid || "";
                }
                if (parsed.bluetooth) {
                    root.btPowered = !!parsed.bluetooth.powered;
                    root.btDiscoverable = !!parsed.bluetooth.discoverable;
                }
                if (parsed.audio) {
                    root.audioVolume = (typeof parsed.audio.volume === "number") ? parsed.audio.volume : root.audioVolume;
                    root.audioMuted = !!parsed.audio.muted;
                    root.micVolume = (typeof parsed.audio.micVolume === "number") ? parsed.audio.micVolume : root.micVolume;
                    root.micMuted = !!parsed.audio.micMuted;
                }
                if (parsed.system) {
                    root.sysBrightness = (typeof parsed.system.brightness === "number") ? parsed.system.brightness : root.sysBrightness;
                    root.sysNightLight = !!parsed.system.nightLight;
                    root.sysCaffeine = !!parsed.system.caffeine;
                    root.sysDnd = !!parsed.system.dnd;
                    root.sysAirplane = !!parsed.system.airplane;
                }
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
        actionProc.command = [root.minimalRoot + "/scripts/control-center-actions.sh"].concat(args);
        actionProc.running = true;
    }

    Process {
        id: actionProc
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: {
                if (text && text.trim()) root.lastActionError = text.trim();
            }
        }
        onExited: (exitCode) => {
            root.busy = false;
            if (exitCode !== 0 && root.connectingWifiSsid !== "") {
                var err = root.lastActionError || ("Failed to connect to " + root.connectingWifiSsid);
                if (err.indexOf("Error:") === 0) err = err.slice(6).trim();
                root.wifiError = err;
            } else if (exitCode === 0 && root.connectingWifiSsid !== "") {
                root.wifiError = "";
            }
            root.lastActionError = "";
            root.connectingWifiSsid = "";
            root.connectingBtMac = "";
            root.connectingBtAction = "";
            pollProc.running = true;
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
        pollProc.running = true;
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
            focus: root.pendingSsid === ""
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
                                    icon: root.wifiEnabled ? "󰖩" : "󰖪",
                                    title: "Wi-Fi",
                                    sub: root.wifiConnectedSsid || (root.wifiEnabled ? "On" : "Off"),
                                    active: root.wifiEnabled,
                                    act: ["wifi-toggle"],
                                    toggleLocal: () => { root.wifiEnabled = !root.wifiEnabled; },
                                    moreTab: "wifi"
                                },
                                {
                                    icon: root.btPowered ? "󰂯" : "󰂲",
                                    title: "Bluetooth",
                                    sub: root.btPowered ? "Powered On" : "Off",
                                    active: root.btPowered,
                                    act: ["bt-toggle"],
                                    toggleLocal: () => { root.btPowered = !root.btPowered; },
                                    moreTab: "bluetooth"
                                },
                                {
                                    icon: "󰀝",
                                    title: "Airplane",
                                    sub: root.sysAirplane ? "Active" : "Off",
                                    active: root.sysAirplane,
                                    act: ["airplane-toggle"],
                                    toggleLocal: () => { root.sysAirplane = !root.sysAirplane; },
                                    moreTab: ""
                                },
                                {
                                    icon: "󰖔",
                                    title: "Night Light",
                                    sub: root.sysNightLight ? "Warm 4500K" : "Off",
                                    active: root.sysNightLight,
                                    act: ["nightlight-toggle"],
                                    toggleLocal: () => { root.sysNightLight = !root.sysNightLight; },
                                    moreTab: ""
                                },
                                {
                                    icon: "󰅶",
                                    title: "Caffeine",
                                    sub: root.sysCaffeine ? "Awake" : "Normal Idle",
                                    active: root.sysCaffeine,
                                    act: ["caffeine-toggle"],
                                    toggleLocal: () => { root.sysCaffeine = !root.sysCaffeine; },
                                    moreTab: ""
                                },
                                {
                                    icon: "󰂛",
                                    title: "Do Not Disturb",
                                    sub: root.sysDnd ? "Silenced" : "Alerts On",
                                    active: root.sysDnd,
                                    act: ["dnd-toggle"],
                                    toggleLocal: () => { root.sysDnd = !root.sysDnd; },
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
                                            modelData.toggleLocal();
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
                                        icon: root.audioMuted ? "󰝟" : "󰕾",
                                        label: "Speaker",
                                        val: root.audioVolume,
                                        max: 100,
                                        muteAct: ["audio-mute"],
                                        setAct: "audio-volume",
                                        setLocal: (pct) => { root.audioVolume = pct; root.audioMuted = false; },
                                        toggleMuteLocal: () => { root.audioMuted = !root.audioMuted; }
                                    },
                                    {
                                        icon: root.micMuted ? "󰍭" : "󰍬",
                                        label: "Mic",
                                        val: root.micVolume,
                                        max: 100,
                                        muteAct: ["mic-mute"],
                                        setAct: "mic-volume",
                                        setLocal: (pct) => { root.micVolume = pct; root.micMuted = false; },
                                        toggleMuteLocal: () => { root.micMuted = !root.micMuted; }
                                    },
                                    {
                                        icon: "󰃠",
                                        label: "Display",
                                        val: root.sysBrightness,
                                        max: 100,
                                        muteAct: [],
                                        setAct: "brightness",
                                        setLocal: (pct) => { root.sysBrightness = pct; },
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
                // TAB 2: FULL WI-FI MANAGER (REDESIGNED)
                // =============================================================
                Item {
                    id: wifiTabItem
                    visible: root.activeTab === "wifi"
                    x: 12; y: 60
                    width: parent.width - 24
                    height: parent.height - 72

                    // Top Control Stack: Header Bar + Error Banner + Search Filter
                    Column {
                        id: wifiTopStack
                        width: parent.width
                        spacing: 8

                        // 1. Wi-Fi Control Header Bar
                        Rectangle {
                            id: wifiHeader
                            width: parent.width; height: 44
                            radius: theme.controlRadius
                            color: theme.control
                            border.width: 1
                            border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                            Row {
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                spacing: 10
                                width: parent.width - 210

                                Text {
                                    text: root.stateData.wifi.enabled ? "󰖩" : "󰖪"
                                    font.family: theme.fontFamily; font.pixelSize: 18
                                    color: root.stateData.wifi.enabled ? theme.accent : theme.muted
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    width: parent.width - 28

                                    Text {
                                        width: parent.width
                                        text: {
                                            if (!root.stateData.wifi.enabled) return "Wi-Fi Disabled";
                                            if (root.stateData.wifi.connectedSsid) return root.stateData.wifi.connectedSsid;
                                            return "Wi-Fi Disconnected";
                                        }
                                        font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: true
                                        color: theme.text
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: {
                                            if (!root.stateData.wifi.enabled) return "Wireless radio turned off";
                                            if (root.stateData.wifi.ipAddress) return "IP: " + root.stateData.wifi.ipAddress + " · " + root.stateData.wifi.interface;
                                            return "Ready to connect";
                                        }
                                        font.family: theme.fontFamily; font.pixelSize: 10
                                        color: theme.muted
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            Row {
                                anchors.right: parent.right; anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                // Hotspot Toggle
                                Rectangle {
                                    width: hsText.implicitWidth + 14; height: 28
                                    radius: Math.max(4, theme.controlRadius - 1)
                                    color: root.stateData.wifi.hotspotActive ? theme.accent : theme.reading
                                    border.width: 1; border.color: root.stateData.wifi.hotspotActive ? theme.accent : theme.border

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
                                    width: 68; height: 28
                                    radius: Math.max(4, theme.controlRadius - 1)
                                    color: theme.reading
                                    border.width: 1; border.color: theme.border

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text {
                                            text: "󰑐"
                                            font.family: theme.fontFamily; font.pixelSize: 12
                                            color: theme.accent
                                            anchors.verticalCenter: parent.verticalCenter
                                            RotationAnimation on rotation {
                                                running: root.busy
                                                loops: Animation.Infinite
                                                from: 0; to: 360; duration: 900
                                            }
                                        }
                                        Text {
                                            text: root.busy ? "Scan…" : "Scan"
                                            font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                            color: theme.accent
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        enabled: !root.busy
                                        onClicked: root.runAction(["wifi-scan"])
                                    }
                                }

                                // Radio Power Toggle Switch
                                Rectangle {
                                    width: 54; height: 28
                                    radius: Math.max(4, theme.controlRadius - 1)
                                    color: root.wifiEnabled ? theme.accent : theme.reading
                                    border.width: 1; border.color: root.wifiEnabled ? theme.accent : theme.border

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Rectangle {
                                            width: 6; height: 6; radius: 3
                                            color: root.wifiEnabled ? theme.base : theme.muted
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: root.wifiEnabled ? "ON" : "OFF"
                                            font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                            color: root.wifiEnabled ? theme.base : theme.muted
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.wifiEnabled = !root.wifiEnabled;
                                            root.runAction(["wifi-toggle"]);
                                        }
                                    }
                                }
                            }
                        }

                        // 2. Wi-Fi Error Banner
                        Rectangle {
                            id: wifiErrorBanner
                            visible: root.wifiError !== ""
                            width: parent.width; height: 32
                            radius: Math.max(4, theme.controlRadius - 1)
                            color: Qt.rgba(0.9, 0.2, 0.2, 0.14)
                            border.width: 1
                            border.color: Qt.rgba(0.9, 0.2, 0.2, 0.45)

                            Row {
                                anchors.left: parent.left; anchors.leftMargin: 10
                                anchors.right: dismissErrBtn.left; anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                Text {
                                    text: "󰅚"
                                    font.family: theme.fontFamily; font.pixelSize: 13
                                    color: Qt.rgba(0.95, 0.35, 0.35, 1)
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    width: parent.width - 24
                                    text: root.wifiError
                                    font.family: theme.fontFamily; font.pixelSize: 11
                                    color: theme.text
                                    elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Rectangle {
                                id: dismissErrBtn
                                anchors.right: parent.right; anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 20; radius: 10
                                color: dismissErrArea.containsMouse ? theme.selection : "transparent"
                                Text {
                                    anchors.centerIn: parent; text: "󰅖"
                                    font.family: theme.fontFamily; font.pixelSize: 11
                                    color: theme.muted
                                }
                                MouseArea {
                                    id: dismissErrArea
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: root.wifiError = ""
                                }
                            }
                        }

                        // 3. Search Filter Bar
                        Rectangle {
                            id: wifiSearchRow
                            visible: root.stateData.wifi.enabled && (root.connectedWifiNetworks.length > 0 || root.availableWifiNetworks.length > 0 || root.wifiSearchText !== "")
                            width: parent.width; height: 32
                            radius: Math.max(4, theme.controlRadius - 1)
                            color: theme.control
                            border.width: 1
                            border.color: wifiSearchField.activeFocus ? theme.accent : Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 10; anchors.rightMargin: 8
                                spacing: 8

                                Text {
                                    text: "󰍉"
                                    font.family: theme.fontFamily; font.pixelSize: 13
                                    color: wifiSearchField.activeFocus ? theme.accent : theme.muted
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                TextInput {
                                    id: wifiSearchField
                                    width: parent.width - (clearFilterBtn.visible ? 48 : 28)
                                    height: parent.height
                                    verticalAlignment: TextInput.AlignVCenter
                                    font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary
                                    color: theme.text; selectionColor: theme.selection
                                    clip: true
                                    text: root.wifiSearchText
                                    onTextChanged: root.wifiSearchText = text

                                    Text {
                                        visible: !wifiSearchField.text && !wifiSearchField.activeFocus
                                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                        text: "Filter networks by name..."
                                        font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary
                                        color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.35)
                                    }
                                }

                                Rectangle {
                                    id: clearFilterBtn
                                    visible: root.wifiSearchText !== ""
                                    width: 20; height: 20; radius: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: clearFilterArea.containsMouse ? theme.selection : "transparent"
                                    Text {
                                        anchors.centerIn: parent; text: "󰅖"
                                        font.family: theme.fontFamily; font.pixelSize: 11
                                        color: theme.muted
                                    }
                                    MouseArea {
                                        id: clearFilterArea
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                        onClicked: {
                                            root.wifiSearchText = "";
                                            wifiSearchField.text = "";
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Network Delegate Component
                    Component {
                        id: wifiCardDelegate

                        Rectangle {
                            id: wifiCard
                            required property var modelData
                            readonly property bool isPending: root.pendingSsid === modelData.ssid
                            readonly property bool isConnecting: root.connectingWifiSsid === modelData.ssid

                            width: wifiCol.width
                            height: isPending ? 104 : 48
                            radius: theme.controlRadius
                            color: (modelData.inUse || isPending)
                                ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.12)
                                : (cardHover.containsMouse ? Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.05) : theme.control)
                            border.width: 1
                            border.color: (modelData.inUse || isPending)
                                ? theme.accent
                                : (cardHover.containsMouse ? Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.22) : Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.07))
                            clip: true

                            Behavior on height {
                                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                            }

                            // Full card interaction
                            MouseArea {
                                id: cardHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !wifiCard.isPending && !wifiCard.isConnecting
                                onClicked: {
                                    if (modelData.inUse) {
                                        root.runAction(["wifi-disconnect", modelData.ssid]);
                                    } else if (modelData.saved || !modelData.secured) {
                                        root.wifiError = "";
                                        root.connectingWifiSsid = modelData.ssid;
                                        root.runAction(["wifi-connect", modelData.ssid]);
                                    } else {
                                        root.wifiError = "";
                                        root.pendingSsid = modelData.ssid;
                                        root.wifiPassword = "";
                                        root.showWifiPassword = false;
                                    }
                                }
                            }

                            // Main network info row
                            Item {
                                id: mainRow
                                width: parent.width; height: 48

                                Row {
                                    x: 12; anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10
                                    width: parent.width - 150

                                    Text {
                                        text: modelData.signal >= 75 ? "󰤨" : (modelData.signal >= 50 ? "󰤥" : (modelData.signal >= 25 ? "󰤢" : "󰤟"))
                                        font.family: theme.fontFamily; font.pixelSize: 16
                                        color: modelData.inUse ? theme.accent : (modelData.signal >= 50 ? theme.text : theme.muted)
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Column {
                                        width: parent.width - 32
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2

                                        Row {
                                            spacing: 6
                                            width: parent.width

                                            Text {
                                                text: modelData.ssid
                                                elide: Text.ElideRight
                                                font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: modelData.inUse || modelData.saved
                                                color: theme.text
                                                maximumLineCount: 1
                                            }

                                            // SAVED Pill
                                            Rectangle {
                                                visible: modelData.saved && !modelData.inUse
                                                width: savedPillTxt.implicitWidth + 8; height: 15; radius: 3
                                                color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.18)
                                                anchors.verticalCenter: parent.verticalCenter
                                                Text {
                                                    id: savedPillTxt
                                                    anchors.centerIn: parent; text: "SAVED"
                                                    font.family: theme.fontFamily; font.pixelSize: 8; font.bold: true
                                                    color: theme.accent
                                                }
                                            }

                                            // Band badge (5G / 2.4G)
                                            Rectangle {
                                                visible: !!modelData.band
                                                width: bandPillTxt.implicitWidth + 8; height: 15; radius: 3
                                                color: theme.reading
                                                border.width: 1; border.color: theme.border
                                                anchors.verticalCenter: parent.verticalCenter
                                                Text {
                                                    id: bandPillTxt
                                                    anchors.centerIn: parent
                                                    text: modelData.band ? (modelData.band.indexOf("5") !== -1 ? "5G" : (modelData.band.indexOf("2") !== -1 ? "2.4G" : modelData.band)) : ""
                                                    font.family: theme.fontFamily; font.pixelSize: 8; font.bold: true
                                                    color: theme.muted
                                                }
                                            }
                                        }

                                        Row {
                                            spacing: 6
                                            Text {
                                                text: isConnecting
                                                    ? "Connecting..."
                                                    : (modelData.signal + "%  ·  " + (modelData.secured ? (modelData.security || "Secured") : "Open"))
                                                font.family: theme.fontFamily; font.pixelSize: 10
                                                color: isConnecting ? theme.accent : theme.muted
                                            }
                                        }
                                    }
                                }

                                Row {
                                    anchors.right: parent.right; anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    // Forget saved profile button
                                    Rectangle {
                                        visible: modelData.saved && !modelData.inUse
                                        width: 28; height: 28
                                        radius: Math.max(4, theme.controlRadius - 1)
                                        color: theme.reading
                                        border.width: 1; border.color: cardForgetArea.containsMouse ? theme.accent : theme.border
                                        Text {
                                            anchors.centerIn: parent; text: "󰆴"
                                            font.family: theme.fontFamily; font.pixelSize: 13
                                            color: cardForgetArea.containsMouse ? theme.accent : theme.muted
                                        }
                                        MouseArea {
                                            id: cardForgetArea
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                            onClicked: root.runAction(["wifi-forget", modelData.ssid])
                                        }
                                    }

                                    // Connect / Disconnect button
                                    Rectangle {
                                        width: 78; height: 28
                                        radius: Math.max(4, theme.controlRadius - 1)
                                        color: modelData.inUse ? theme.reading : theme.accent
                                        border.width: 1; border.color: modelData.inUse ? theme.border : theme.accent
                                        opacity: isConnecting ? 0.7 : 1.0

                                        Text {
                                            anchors.centerIn: parent
                                            text: isConnecting ? "…" : (modelData.inUse ? "Disconnect" : (isPending ? "Cancel" : "Connect"))
                                            font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                            color: modelData.inUse ? theme.text : theme.base
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            enabled: !isConnecting
                                            onClicked: {
                                                if (modelData.inUse) {
                                                    root.runAction(["wifi-disconnect", modelData.ssid]);
                                                } else if (modelData.saved || !modelData.secured) {
                                                    root.wifiError = "";
                                                    root.connectingWifiSsid = modelData.ssid;
                                                    root.runAction(["wifi-connect", modelData.ssid]);
                                                } else {
                                                    if (root.pendingSsid === modelData.ssid) {
                                                        root.pendingSsid = "";
                                                        root.wifiPassword = "";
                                                    } else {
                                                        root.wifiError = "";
                                                        root.pendingSsid = modelData.ssid;
                                                        root.wifiPassword = "";
                                                        root.showWifiPassword = false;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Inline expandable password input drawer
                            Rectangle {
                                id: inlinePassRow
                                visible: wifiCard.isPending
                                x: 10; y: 52
                                width: parent.width - 20; height: 44
                                radius: Math.max(4, theme.controlRadius - 2)
                                color: theme.reading
                                border.width: 1; border.color: theme.border

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10; anchors.rightMargin: 6
                                    spacing: 6

                                    Text {
                                        id: lockIcon
                                        text: "󰌾"
                                        font.family: theme.fontFamily; font.pixelSize: 14
                                        color: theme.accent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Item {
                                        width: parent.width - lockIcon.width - passEyeBtn.width - cardJoinBtn.width - cardCancelBtn.width - 34
                                        height: parent.height
                                        anchors.verticalCenter: parent.verticalCenter

                                        TextInput {
                                            id: cardPassInput
                                            anchors.fill: parent
                                            verticalAlignment: TextInput.AlignVCenter
                                            echoMode: root.showWifiPassword ? TextInput.Normal : TextInput.Password
                                            font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary
                                            color: theme.text; selectionColor: theme.selection
                                            clip: true
                                            text: wifiCard.isPending ? root.wifiPassword : ""
                                            onTextChanged: {
                                                if (wifiCard.isPending) root.wifiPassword = text;
                                            }
                                            Component.onCompleted: {
                                                if (wifiCard.isPending) forceActiveFocus();
                                            }
                                            Keys.onReturnPressed: {
                                                const target = modelData.ssid;
                                                const pw = root.wifiPassword;
                                                root.pendingSsid = "";
                                                root.wifiPassword = "";
                                                root.showWifiPassword = false;
                                                root.connectingWifiSsid = target;
                                                root.wifiError = "";
                                                root.runAction(["wifi-connect", target, pw]);
                                            }
                                            Keys.onEscapePressed: {
                                                root.pendingSsid = "";
                                                root.wifiPassword = "";
                                                root.showWifiPassword = false;
                                            }
                                        }

                                        Text {
                                            visible: !cardPassInput.text && !cardPassInput.activeFocus
                                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                            text: "Enter Wi-Fi password..."
                                            font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary
                                            color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.4)
                                        }
                                    }

                                    Rectangle {
                                        id: passEyeBtn
                                        width: 28; height: 28
                                        radius: 4
                                        anchors.verticalCenter: parent.verticalCenter
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
                                        id: cardJoinBtn
                                        width: 54; height: 28
                                        radius: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: theme.accent
                                        Text {
                                            anchors.centerIn: parent; text: "Join"
                                            font.family: theme.fontFamily; font.pixelSize: 11; font.bold: true
                                            color: theme.base
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const target = modelData.ssid;
                                                const pw = root.wifiPassword;
                                                root.pendingSsid = "";
                                                root.wifiPassword = "";
                                                root.showWifiPassword = false;
                                                root.connectingWifiSsid = target;
                                                root.wifiError = "";
                                                root.runAction(["wifi-connect", target, pw]);
                                            }
                                        }
                                    }

                                    Rectangle {
                                        id: cardCancelBtn
                                        width: 28; height: 28
                                        radius: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: cardCancelArea.containsMouse ? theme.selection : "transparent"
                                        Text {
                                            anchors.centerIn: parent; text: "󰅖"
                                            font.family: theme.fontFamily; font.pixelSize: 13
                                            color: theme.muted
                                        }
                                        MouseArea {
                                            id: cardCancelArea
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onClicked: {
                                                root.pendingSsid = "";
                                                root.wifiPassword = "";
                                                root.showWifiPassword = false;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Scrollable Networks Container
                    Flickable {
                        id: wifiFlick
                        anchors.top: wifiTopStack.bottom
                        anchors.topMargin: 8
                        anchors.bottom: parent.bottom
                        width: parent.width
                        contentWidth: width
                        contentHeight: wifiCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { width: 3; policy: ScrollBar.AsNeeded }

                        Column {
                            id: wifiCol
                            width: parent.width
                            spacing: 8

                            // Disabled state card
                            Rectangle {
                                visible: !root.stateData.wifi.enabled
                                width: parent.width; height: 200
                                radius: theme.controlRadius
                                color: theme.control
                                border.width: 1
                                border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 12

                                    Text {
                                        text: "󰖪"
                                        font.family: theme.fontFamily; font.pixelSize: 42
                                        color: theme.muted
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    Column {
                                        spacing: 4
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        Text {
                                            text: "Wi-Fi is Turned Off"
                                            font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: true
                                            color: theme.text
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                        Text {
                                            text: "Enable Wi-Fi to scan and connect to nearby networks"
                                            font.family: theme.fontFamily; font.pixelSize: 11
                                            color: theme.muted
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                    }

                                    Rectangle {
                                        width: 140; height: 32
                                        radius: Math.max(4, theme.controlRadius - 1)
                                        color: theme.accent
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 8
                                            Text {
                                                text: "󰖩"
                                                font.family: theme.fontFamily; font.pixelSize: 13
                                                color: theme.base
                                            }
                                            Text {
                                                text: "Turn On Wi-Fi"
                                                font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                                color: theme.base
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.wifiEnabled = true;
                                                root.runAction(["wifi-toggle"]);
                                            }
                                        }
                                    }
                                }
                            }

                            // Active Connection Hero Card
                            Rectangle {
                                visible: root.stateData.wifi.enabled && root.connectedWifiNetworks.length > 0
                                width: parent.width; height: 72
                                radius: theme.controlRadius
                                color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.12)
                                border.width: 1
                                border.color: theme.accent

                                Item {
                                    anchors.fill: parent
                                    anchors.margins: 10

                                    Row {
                                        anchors.left: parent.left
                                        anchors.right: heroActions.left
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 10

                                        Text {
                                            readonly property int sig: root.connectedWifiNetworks.length > 0 ? (root.connectedWifiNetworks[0].signal || 0) : 0
                                            text: sig >= 75 ? "󰤨" : (sig >= 50 ? "󰤥" : (sig >= 25 ? "󰤢" : "󰤟"))
                                            font.family: theme.fontFamily; font.pixelSize: 22
                                            color: theme.accent
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 4
                                            width: parent.width - 34

                                            Row {
                                                spacing: 6
                                                width: parent.width

                                                Text {
                                                    text: root.stateData.wifi.connectedSsid || (root.connectedWifiNetworks.length > 0 ? root.connectedWifiNetworks[0].ssid : "Connected")
                                                    font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: true
                                                    color: theme.text
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 1
                                                }

                                                Rectangle {
                                                    width: 52; height: 16; radius: 3
                                                    color: theme.accent
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    Text {
                                                        anchors.centerIn: parent; text: "ACTIVE"
                                                        font.family: theme.fontFamily; font.pixelSize: 9; font.bold: true
                                                        color: theme.base
                                                    }
                                                }

                                                Rectangle {
                                                    visible: root.connectedWifiNetworks.length > 0 && !!root.connectedWifiNetworks[0].band
                                                    width: bandHeroTxt.implicitWidth + 8; height: 16; radius: 3
                                                    color: theme.reading
                                                    border.width: 1; border.color: theme.border
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    Text {
                                                        id: bandHeroTxt
                                                        anchors.centerIn: parent
                                                        text: root.connectedWifiNetworks.length > 0 ? (root.connectedWifiNetworks[0].band || "") : ""
                                                        font.family: theme.fontFamily; font.pixelSize: 9; font.bold: true
                                                        color: theme.muted
                                                    }
                                                }
                                            }

                                            Row {
                                                spacing: 8
                                                Text {
                                                    readonly property int sig: root.connectedWifiNetworks.length > 0 ? (root.connectedWifiNetworks[0].signal || 0) : 0
                                                    text: sig + "% signal"
                                                    font.family: theme.fontFamily; font.pixelSize: 10
                                                    color: theme.accent
                                                }
                                                Text {
                                                    visible: root.stateData.wifi.ipAddress !== ""
                                                    text: "·  IP: " + root.stateData.wifi.ipAddress
                                                    font.family: theme.fontFamily; font.pixelSize: 10
                                                    color: theme.muted
                                                }
                                                Text {
                                                    visible: root.stateData.wifi.interface !== ""
                                                    text: "(" + root.stateData.wifi.interface + ")"
                                                    font.family: theme.fontFamily; font.pixelSize: 10
                                                    color: theme.muted
                                                }
                                            }
                                        }
                                    }

                                    Row {
                                        id: heroActions
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6

                                        Rectangle {
                                            width: 86; height: 28
                                            radius: Math.max(4, theme.controlRadius - 1)
                                            color: theme.reading
                                            border.width: 1
                                            border.color: heroDiscArea.containsMouse ? theme.accent : theme.border

                                            Text {
                                                anchors.centerIn: parent
                                                text: "Disconnect"
                                                font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                                color: theme.text
                                            }
                                            MouseArea {
                                                id: heroDiscArea
                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                                onClicked: {
                                                    const target = root.stateData.wifi.connectedSsid || (root.connectedWifiNetworks.length > 0 ? root.connectedWifiNetworks[0].ssid : "");
                                                    if (target) root.runAction(["wifi-disconnect", target]);
                                                }
                                            }
                                        }

                                        Rectangle {
                                            visible: root.connectedWifiNetworks.length > 0 && root.connectedWifiNetworks[0].saved
                                            width: 28; height: 28
                                            radius: Math.max(4, theme.controlRadius - 1)
                                            color: theme.reading
                                            border.width: 1
                                            border.color: heroForgetArea.containsMouse ? theme.accent : theme.border
                                            Text {
                                                anchors.centerIn: parent; text: "󰆴"
                                                font.family: theme.fontFamily; font.pixelSize: 13
                                                color: heroForgetArea.containsMouse ? theme.accent : theme.muted
                                            }
                                            MouseArea {
                                                id: heroForgetArea
                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                                onClicked: {
                                                    const target = root.stateData.wifi.connectedSsid || (root.connectedWifiNetworks.length > 0 ? root.connectedWifiNetworks[0].ssid : "");
                                                    if (target) root.runAction(["wifi-forget", target]);
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Available Networks Section Header
                            Row {
                                visible: root.stateData.wifi.enabled && root.availableWifiNetworks.length > 0
                                width: parent.width
                                spacing: 8

                                Text {
                                    text: "AVAILABLE NETWORKS"
                                    color: theme.muted
                                    font.family: theme.fontFamily; font.pixelSize: 10; font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Rectangle {
                                    width: countTxt.implicitWidth + 8; height: 16; radius: 8
                                    color: theme.control
                                    border.width: 1; border.color: theme.border
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        id: countTxt
                                        anchors.centerIn: parent
                                        text: root.availableWifiNetworks.length
                                        font.family: theme.fontFamily; font.pixelSize: 9
                                        color: theme.muted
                                    }
                                }
                            }

                            // Available Networks List
                            Repeater {
                                model: root.availableWifiNetworks
                                delegate: wifiCardDelegate
                            }

                            // Empty search / No networks state
                            Rectangle {
                                visible: root.stateData.wifi.enabled && root.connectedWifiNetworks.length === 0 && root.availableWifiNetworks.length === 0
                                width: parent.width; height: 160
                                radius: theme.controlRadius
                                color: theme.control
                                border.width: 1
                                border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 10

                                    Text {
                                        text: root.busy ? "󰑐" : "󰖩"
                                        font.family: theme.fontFamily; font.pixelSize: 32
                                        color: theme.accent
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        RotationAnimation on rotation {
                                            running: root.busy
                                            loops: Animation.Infinite
                                            from: 0; to: 360; duration: 1000
                                        }
                                    }

                                    Column {
                                        spacing: 4
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        Text {
                                            text: root.busy ? "Scanning for Networks..." : (root.wifiSearchText !== "" ? "No Networks Match Filter" : "No Networks Found")
                                            font.family: theme.fontFamily; font.pixelSize: theme.fontBody; font.bold: true
                                            color: theme.text
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                        Text {
                                            text: root.wifiSearchText !== "" ? ("No network name matching \"" + root.wifiSearchText + "\"") : "Ensure your wireless device is in range and active."
                                            font.family: theme.fontFamily; font.pixelSize: 11
                                            color: theme.muted
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                    }

                                    Rectangle {
                                        width: 100; height: 28
                                        radius: Math.max(4, theme.controlRadius - 1)
                                        color: theme.reading
                                        border.width: 1; border.color: theme.border
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: root.wifiSearchText !== "" ? "Clear Filter" : "󰑐 Scan"
                                            font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                            color: theme.accent
                                        }

                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.wifiSearchText !== "") {
                                                    root.wifiSearchText = "";
                                                } else {
                                                    root.runAction(["wifi-scan"]);
                                                }
                                            }
                                        }
                                    }
                                }
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
                                color: root.btDiscoverable ? theme.accent : theme.reading
                                border.width: 1; border.color: theme.border
                                Text {
                                    anchors.centerIn: parent
                                    text: root.btDiscoverable ? "Discoverable" : "Hidden"
                                    font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                    color: root.btDiscoverable ? theme.base : theme.text
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.btDiscoverable = !root.btDiscoverable;
                                        root.runAction(["bt-discoverable"]);
                                    }
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
                                color: root.btPowered ? theme.accent : theme.reading
                                border.width: 1; border.color: theme.border
                                Text {
                                    anchors.centerIn: parent
                                    text: root.btPowered ? "ON" : "OFF"
                                    font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                    color: root.btPowered ? theme.base : theme.muted
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.btPowered = !root.btPowered;
                                        root.runAction(["bt-toggle"]);
                                    }
                                }
                            }
                        }
                    }

                    Component {
                        id: btCardDelegate

                        Rectangle {
                            required property var modelData
                            readonly property bool isConnecting: root.connectingBtMac === modelData.mac

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
                                        text: isConnecting
                                            ? (root.connectingBtAction === "pair" ? "Pairing..." : "Connecting...")
                                            : ((modelData.connected ? "Connected" : (modelData.paired ? "Paired" : "Available"))
                                                + (modelData.trusted ? " · Trusted" : "")
                                                + (modelData.battery ? (" · 󰁹 " + modelData.battery) : ""))
                                        font.family: theme.fontFamily; font.pixelSize: 10
                                        color: (modelData.connected || isConnecting) ? theme.accent : theme.muted
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
                                    opacity: isConnecting ? 0.7 : 1.0

                                    Text {
                                        anchors.centerIn: parent
                                        text: isConnecting ? "…" : (modelData.connected ? "Disconnect" : (modelData.paired ? "Connect" : "Pair"))
                                        font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary; font.bold: true
                                        color: modelData.connected ? theme.text : theme.base
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        enabled: !isConnecting
                                        onClicked: {
                                            if (modelData.connected) {
                                                root.runAction(["bt-disconnect", modelData.mac]);
                                            } else if (modelData.paired) {
                                                root.connectingBtMac = modelData.mac;
                                                root.connectingBtAction = "connect";
                                                root.runAction(["bt-connect", modelData.mac]);
                                            } else {
                                                root.connectingBtMac = modelData.mac;
                                                root.connectingBtAction = "pair";
                                                root.runAction(["bt-pair", modelData.mac]);
                                            }
                                        }
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
