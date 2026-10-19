import "../"
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: page

    property bool wifiEnabled: true
    property var networks: []
    property var savedNetworks: []
    property string connectingSsid: ""
    property string connectError: ""
    property string pendingPassword: ""
    property bool showPassword: false
    readonly property var connectedNetworks: {
        var res = [];
        for (var i = 0; i < page.networks.length; i++) {
            if (page.networks[i].connected)
                res.push(page.networks[i]);
        }
        return res;
    }
    readonly property var availableNetworks: {
        var res = [];
        for (var i = 0; i < page.networks.length; i++) {
            if (!page.networks[i].connected)
                res.push(page.networks[i]);
        }
        return res;
    }
    property string pendingSsid: ""
    property var ethernet: ({
        "device": "",
        "state": "disconnected",
        "connection": ""
    })
    property string monoFont: Theme.monoFont
    property real downSpeed: 0
    property real upSpeed: 0
    property real lastRx: -1
    property real lastTx: -1
    property real lastTs: 0
    property real marginLeft: 0
    property real marginRight: 12
    property real marginTop: 0
    property real marginBottom: 0
    readonly property string icDown: "\uf019"
    readonly property string icUp: "\uf093"
    readonly property string icWifi: "\uf1eb"
    readonly property string icLock: "\uf023"
    readonly property string icEth: "\uf6ff"
    readonly property string icEye: "\uf06e"
    readonly property string icEyeOff: "\uf070"
    readonly property string icForget: "\uf1f8"

    function formatSpeed(bps) {
        if (bps < 1024)
            return bps.toFixed(0) + " B/s";

        if (bps < 1024 * 1024)
            return (bps / 1024).toFixed(1) + " KB/s";

        if (bps < 1024 * 1024 * 1024)
            return (bps / 1024 / 1024).toFixed(2) + " MB/s";

        return (bps / 1024 / 1024 / 1024).toFixed(2) + " GB/s";
    }

    function setWifiEnabled(on) {
        page.wifiEnabled = on;
        pRadioSet.command = ["nmcli", "radio", "wifi", on ? "on" : "off"];
        pRadioSet.running = true;
    }

    function rescanWifi() {
        if (!pRescan.running)
            pRescan.running = true;
    }

    function connectOpen(ssid) {
        page.connectingSsid = ssid;
        page.connectError = "";
        pConnect.command = ["python3", Quickshell.shellDir + "/../../scripts/network-action.py", "connect", ssid];
        pConnect.running = true;
    }

    function connectSaved(ssid) {
        page.connectingSsid = ssid;
        page.connectError = "";
        pConnect.command = ["python3", Quickshell.shellDir + "/../../scripts/network-action.py", "connect", ssid];
        pConnect.running = true;
    }

    function connectSecured(ssid, password) {
        var pw = (password || "").trim();
        if (!pw) {
            page.connectError = "Please enter a password";
            return;
        }
        page.connectingSsid = ssid;
        page.connectError = "";
        pConnect.command = ["python3", Quickshell.shellDir + "/../../scripts/network-action.py", "connect", ssid, pw];
        pConnect.running = true;
    }

    function disconnect(ssid) {
        page.connectingSsid = ssid;
        page.connectError = "";
        pConnect.command = ["python3", Quickshell.shellDir + "/../../scripts/network-action.py", "disconnect", ssid];
        pConnect.running = true;
    }

    function forget(ssid) {
        page.connectError = "";
        pConnect.command = ["python3", Quickshell.shellDir + "/../../scripts/network-action.py", "forget", ssid];
        pConnect.running = true;
    }

    Component.onCompleted: {
        pRadioGet.running = true;
        pSaved.running = true;
        pRescan.running = true;
        pList.running = true;
        pEthernet.running = true;
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!pRadioGet.running)
                pRadioGet.running = true;
        }
    }

    Timer {
        interval: 5000
        running: page.wifiEnabled && page.connectingSsid === "" && page.pendingSsid === ""
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (page.wifiEnabled && !pList.running && page.connectingSsid === "" && page.pendingSsid === "")
                pList.running = true;
        }
    }

    Process {
        id: pNet

        command: ["cat", "/proc/net/dev"]

        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.split("\n");
                var rx = 0;
                var tx = 0;
                for (var i = 2; i < lines.length; ++i) {
                    var line = lines[i].trim();
                    if (!line)
                        continue;

                    var idx = line.indexOf(":");
                    if (idx < 0)
                        continue;

                    var name = line.slice(0, idx).trim();
                    if (name === "lo" || name.indexOf("veth") === 0 || name.indexOf("docker") === 0 || name.indexOf("br-") === 0 || name.indexOf("virbr") === 0)
                        continue;

                    var parts = line.slice(idx + 1).trim().split(/\s+/);
                    rx += parseFloat(parts[0]) || 0;
                    tx += parseFloat(parts[8]) || 0;
                }
                var now = Date.now();
                if (page.lastTs > 0) {
                    var dt = (now - page.lastTs) / 1000;
                    if (dt > 0) {
                        page.downSpeed = Math.max(0, (rx - page.lastRx) / dt);
                        page.upSpeed = Math.max(0, (tx - page.lastTx) / dt);
                    }
                }
                page.lastRx = rx;
                page.lastTx = tx;
                page.lastTs = now;
            }
        }

    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!pNet.running)
                pNet.running = true;

        }
    }

    Process {
        id: pEthernet

        command: ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"]

        stdout: StdioCollector {
            onStreamFinished: {
                var result = {
                    "device": "",
                    "state": "disconnected",
                    "connection": ""
                };
                var raw = text.trim();
                if (raw) {
                    var lines = raw.split("\n");
                    for (var i = 0; i < lines.length; ++i) {
                        var line = lines[i].trim();
                        if (!line)
                            continue;

                        var fields = line.split(":");
                        if (fields.length < 4)
                            continue;

                        if (fields[1] === "ethernet") {
                            result.device = fields[0];
                            result.state = fields[2];
                            result.connection = fields.slice(3).join(":");
                            break;
                        }
                    }
                }
                page.ethernet = result;
            }
        }

        stderr: StdioCollector {
        }

    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!pEthernet.running)
                pEthernet.running = true;

        }
    }

    Process {
        id: pRadioGet

        command: ["nmcli", "radio", "wifi"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                page.wifiEnabled = text.trim() === "enabled";
                if (page.wifiEnabled && !pList.running)
                    pList.running = true;
            }
        }
    }

    Process {
        id: pSaved
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().split("\n");
                var saved = [];
                for (var i = 0; i < lines.length; ++i) {
                    var parts = lines[i].split(":");
                    if (parts.length >= 2 && parts[1].indexOf("wireless") !== -1) {
                        saved.push(parts[0].trim());
                    }
                }
                page.savedNetworks = saved;
            }
        }
    }

    Process {
        id: pRescan
        command: ["nmcli", "device", "wifi", "rescan"]
        onExited: {
            pSaved.running = true;
            if (page.wifiEnabled && !pList.running)
                pList.running = true;
        }
    }

    Process {
        id: pRadioSet

        stdout: StdioCollector {
            onStreamFinished: {
                pRadioGet.running = true;
            }
        }
    }

    Process {
        id: pList

        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "no"]

        stdout: StdioCollector {
            onStreamFinished: {
                var out = [];
                var raw = text.trim();
                if (raw) {
                    var lines = raw.split("\n");
                    for (var i = 0; i < lines.length; ++i) {
                        var line = lines[i];
                        if (!line || !line.trim())
                            continue;

                        var fields = [];
                        var current = "";
                        var escaped = false;
                        for (var j = 0; j < line.length; ++j) {
                            var ch = line[j];
                            if (escaped) {
                                current += ch;
                                escaped = false;
                            } else if (ch === "\\") {
                                escaped = true;
                            } else if (ch === ":" && fields.length < 3) {
                                fields.push(current);
                                current = "";
                            } else {
                                current += ch;
                            }
                        }
                        fields.push(current);
                        if (fields.length < 4)
                            continue;

                        var ssid = (fields[1] || "").trim();
                        if (!ssid)
                            continue;

                        var signal = parseInt(fields[2]);
                        if (isNaN(signal))
                            signal = 0;

                        var isConn = fields[0].trim() === "*";
                        var isSaved = page.savedNetworks.indexOf(ssid) !== -1 || isConn;

                        out.push({
                            "ssid": ssid,
                            "signal": signal,
                            "secured": fields[3] !== "" && fields[3] !== "--",
                            "connected": isConn,
                            "saved": isSaved
                        });
                    }
                }

                // Deduplicate SSIDs, keeping strongest signal or connected one
                var map = {};
                for (var k = 0; k < out.length; k++) {
                    var item = out[k];
                    if (!map[item.ssid] || item.connected || item.signal > map[item.ssid].signal) {
                        map[item.ssid] = item;
                    }
                }
                var uniqueList = Object.values(map);
                uniqueList.sort(function(a, b) {
                    if (a.connected) return -1;
                    if (b.connected) return 1;
                    if (a.saved && !b.saved) return -1;
                    if (!a.saved && b.saved) return 1;
                    return b.signal - a.signal;
                });
                page.networks = uniqueList;
            }
        }

        stderr: StdioCollector {
        }

    }

    Process {
        id: pConnect
        property string errorMsg: ""

        stderr: StdioCollector {
            onStreamFinished: {
                if (text && text.trim())
                    pConnect.errorMsg = text.trim();
            }
        }

        onExited: (exitCode) => {
            var targetSsid = page.connectingSsid;
            page.connectingSsid = "";
            pEthernet.running = true;
            pSaved.running = true;

            if (exitCode === 0) {
                page.pendingSsid = "";
                page.pendingPassword = "";
                page.connectError = "";
                pConnect.errorMsg = "";
                if (page.wifiEnabled)
                    pList.running = true;
            } else {
                var err = pConnect.errorMsg || "Connection failed";
                if (err.indexOf("Error:") === 0)
                    err = err.slice(6).trim();
                page.connectError = err;
                pConnect.errorMsg = "";
                if (targetSsid)
                    page.pendingSsid = targetSsid;
                if (page.wifiEnabled)
                    pList.running = true;
            }
        }
    }


    Column {
        anchors.fill: parent
        anchors.leftMargin: page.marginLeft
        anchors.rightMargin: page.marginRight
        anchors.topMargin: page.marginTop
        anchors.bottomMargin: page.marginBottom
        spacing: 14

        Column {
            id: statsRow

            width: parent.width
            spacing: 9

            Rectangle {
                id: wifiToggle

                width: parent.width
                height: 36
                radius: Theme.radius
                color: page.wifiEnabled ? Theme.alpha(Theme.accent, 0.1) : Theme.alpha(Theme.textFaint, 0.15)
                border.width: 1
                border.color: page.wifiEnabled ? Theme.accent : Theme.textFaint

                Text {
                    anchors.centerIn: parent
                    text: page.wifiEnabled ? "WI-FI ON" : "WI-FI OFF"
                    color: page.wifiEnabled ? Theme.accent : Theme.textFaint
                    font.family: page.monoFont
                    font.pixelSize: Theme.fontSecondary
                    font.bold: true
                    font.letterSpacing: 0
                }

                ControlArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.setWifiEnabled(!page.wifiEnabled)
                }
            }

            Row {
                id: statsInner

                width: parent.width
                height: 40
                spacing: 9

                Repeater {
                    model: [{
                        "icon": page.icDown,
                        "label": "DOWNLOAD",
                        "value": page.downSpeed,
                        "down": true
                    }, {
                        "icon": page.icUp,
                        "label": "UPLOAD",
                        "value": page.upSpeed,
                        "down": false
                    }]

                    delegate: Rectangle {
                        required property var modelData

                        width: (statsInner.width - statsInner.spacing) / 2
                        height: statsInner.height
                        radius: Theme.radius
                        color: "#00000000"
                        border.width: 1
                        border.color: Theme.border

                        Text {
                            id: statIcon

                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.icon
                            color: modelData.down ? Theme.accent : Theme.accent2
                            font.family: Theme.iconFont
                            font.pixelSize: 14
                        }

                        Text {
                            anchors.left: statIcon.right
                            anchors.leftMargin: 90
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: Theme.textDim
                            font.family: page.monoFont
                            font.pixelSize: 12
                            font.letterSpacing: 0
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.formatSpeed(modelData.value)
                            color: Theme.text
                            font.family: page.monoFont
                            font.pixelSize: 12
                            font.bold: true
                        }

                    }

                }

            }

        }

        Rectangle {
            id: ethCard

            width: parent.width
            height: 46
            radius: Theme.radius
            color: page.ethernet.state === "connected" ? Theme.alpha(Theme.accent2, 0.1) : "#00000000"
            border.width: 1
            border.color: page.ethernet.state === "connected" ? Theme.accent2 : Theme.border

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9

                Text {
                    text: page.icEth
                    color: page.ethernet.state === "connected" ? Theme.accent2 : Theme.textDim
                    font.family: Theme.iconFont
                    font.pixelSize: 15
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: "Ethernet"
                        color: Theme.text
                        font.family: page.monoFont
                        font.pixelSize: 12
                    }

                    Text {
                        text: page.ethernet.state === "connected" ? (page.ethernet.connection || page.ethernet.device) : "Disconnected"
                        color: Theme.textDim
                        font.family: page.monoFont
                        font.pixelSize: Theme.fontSecondary
                    }

                }

            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: page.ethernet.state === "connected" ? "CONNECTED" : "DISCONNECTED"
                color: page.ethernet.state === "connected" ? Theme.accent2 : Theme.textDim
                font.family: page.monoFont
                font.pixelSize: Theme.fontSecondary
                font.letterSpacing: 0
            }

        }

        Item {
            id: listContainer

            width: parent.width
            height: Math.max(0, page.height - y - page.marginBottom)

            Flickable {
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: list.implicitHeight

                Column {
                    id: list

                    width: parent.width
                    spacing: 6

                    Text {
                        visible: !page.wifiEnabled
                        width: parent.width
                        text: "Wi-Fi is disabled"
                        color: Theme.textDim
                        font.family: page.monoFont
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        visible: page.wifiEnabled && !page.networks.length
                        width: parent.width
                        text: "Scanning Wi-Fi networks"
                        color: Theme.textDim
                        font.family: page.monoFont
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Component {
                        id: wifiCardDelegate

                        Column {
                            required property var modelData

                            width: list.width
                            spacing: 6

                            Rectangle {
                                width: parent.width
                                height: 46
                                radius: Theme.radius
                                color: modelData.connected ? Theme.alpha(Theme.accent, 0.1) : Theme.tint("#ffffff", 0.02)
                                border.width: 1
                                border.color: modelData.connected ? Theme.borderAccent : Theme.border

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 14
                                    anchors.right: actionsRow.left
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 9

                                    Text {
                                        text: page.icWifi
                                        color: modelData.connected ? Theme.accent : Theme.textDim
                                        font.family: Theme.iconFont
                                        font.pixelSize: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        visible: modelData.secured
                                        text: page.icLock
                                        color: Theme.textFaint
                                        font.family: Theme.iconFont
                                        font.pixelSize: Theme.fontSecondary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: modelData.ssid
                                        color: Theme.text
                                        font.family: page.monoFont
                                        font.pixelSize: 12
                                        font.bold: modelData.connected
                                        elide: Text.ElideRight
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Rectangle {
                                        visible: modelData.saved && !modelData.connected
                                        width: savedLabel.implicitWidth + 10
                                        height: 18
                                        radius: Theme.radiusXs
                                        color: Theme.tint(Theme.accent, 0.15)
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            id: savedLabel
                                            anchors.centerIn: parent
                                            text: "SAVED"
                                            color: Theme.accent
                                            font.family: page.monoFont
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                    }
                                }

                                Row {
                                    id: actionsRow
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    // Forget saved network button
                                    Rectangle {
                                        visible: modelData.saved && !modelData.connected
                                        width: 28
                                        height: 28
                                        radius: Theme.radiusSm
                                        color: Theme.tint("#ffffff", 0.04)
                                        border.width: 1
                                        border.color: Theme.border
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: page.icForget
                                            color: Theme.textDim
                                            font.family: Theme.iconFont
                                            font.pixelSize: 11
                                        }

                                        ControlArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            Accessible.name: "Forget " + modelData.ssid
                                            onClicked: page.forget(modelData.ssid)
                                        }
                                    }

                                    // Main Connect / Disconnect button
                                    Rectangle {
                                        id: connectBtnPill
                                        width: Math.max(76, connectBtnLabel.implicitWidth + 20)
                                        height: 28
                                        radius: Theme.radiusSm
                                        color: modelData.connected ? Theme.tint(Theme.danger, 0.12) : Theme.tint(Theme.accent, 0.12)
                                        border.width: 1
                                        border.color: modelData.connected ? Theme.tint(Theme.danger, 0.3) : Theme.tint(Theme.accent, 0.3)
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            id: connectBtnLabel
                                            anchors.centerIn: parent
                                            text: {
                                                if (page.connectingSsid === modelData.ssid)
                                                    return "Connecting…";
                                                if (modelData.connected)
                                                    return "Disconnect";
                                                return "Connect";
                                            }
                                            color: {
                                                if (modelData.connected)
                                                    return Theme.danger;
                                                if (page.connectingSsid === modelData.ssid)
                                                    return Theme.accentSoft;
                                                return Theme.accent;
                                            }
                                            font.family: page.monoFont
                                            font.pixelSize: Theme.fontSecondary
                                            font.bold: true
                                        }

                                        ControlArea {
                                            anchors.fill: parent
                                            enabled: page.connectingSsid !== modelData.ssid
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData.connected) {
                                                    page.disconnect(modelData.ssid);
                                                } else if (modelData.saved) {
                                                    page.connectSaved(modelData.ssid);
                                                } else if (modelData.secured) {
                                                    if (page.pendingSsid === modelData.ssid) {
                                                        page.pendingSsid = "";
                                                        page.pendingPassword = "";
                                                        page.connectError = "";
                                                    } else {
                                                        page.pendingSsid = modelData.ssid;
                                                        page.pendingPassword = "";
                                                        page.connectError = "";
                                                    }
                                                } else {
                                                    page.connectOpen(modelData.ssid);
                                                }
                                            }
                                        }
                                    }
                                }

                                ControlArea {
                                    anchors.left: parent.left
                                    anchors.right: actionsRow.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (page.connectingSsid === modelData.ssid)
                                            return;
                                        if (modelData.connected) {
                                            page.disconnect(modelData.ssid);
                                        } else if (modelData.saved) {
                                            page.connectSaved(modelData.ssid);
                                        } else if (modelData.secured) {
                                            if (page.pendingSsid === modelData.ssid) {
                                                page.pendingSsid = "";
                                                page.pendingPassword = "";
                                                page.connectError = "";
                                            } else {
                                                page.pendingSsid = modelData.ssid;
                                                page.pendingPassword = "";
                                                page.connectError = "";
                                            }
                                        } else {
                                            page.connectOpen(modelData.ssid);
                                        }
                                    }
                                }
                            }

                            Column {
                                visible: page.pendingSsid === modelData.ssid
                                width: parent.width
                                spacing: 6

                                Row {
                                    width: parent.width
                                    height: 34
                                    spacing: 8

                                    Rectangle {
                                        width: Math.min(320, parent.width - 130)
                                        height: 34
                                        color: Theme.bgCard
                                        border.color: page.connectError ? Theme.danger : Theme.accent
                                        border.width: 1
                                        radius: Theme.radiusSm

                                        TextInput {
                                            id: pwField
                                            anchors.left: parent.left
                                            anchors.leftMargin: 10
                                            anchors.right: eyeBtn.left
                                            anchors.rightMargin: 6
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: Theme.text
                                            font.family: page.monoFont
                                            font.pixelSize: 12
                                            echoMode: page.showPassword ? TextInput.Normal : TextInput.Password
                                            focus: page.pendingSsid === modelData.ssid
                                            text: page.pendingPassword
                                            onTextChanged: page.pendingPassword = text
                                            Keys.onReturnPressed: {
                                                if (page.connectingSsid !== modelData.ssid)
                                                    page.connectSecured(modelData.ssid, text);
                                            }
                                            Keys.onEscapePressed: {
                                                page.pendingSsid = "";
                                                page.pendingPassword = "";
                                                page.connectError = "";
                                            }

                                            Text {
                                                visible: !pwField.text && !pwField.activeFocus
                                                anchors.fill: parent
                                                text: "Enter password…"
                                                color: Theme.textDim
                                                font.family: page.monoFont
                                                font.pixelSize: 12
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                        }

                                        Rectangle {
                                            id: eyeBtn
                                            anchors.right: parent.right
                                            anchors.rightMargin: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 26
                                            height: 26
                                            radius: Theme.radiusXs
                                            color: eyeArea.containsMouse ? Theme.bgHover : "transparent"

                                            Text {
                                                anchors.centerIn: parent
                                                text: page.showPassword ? page.icEyeOff : page.icEye
                                                color: page.showPassword ? Theme.accent : Theme.textDim
                                                font.family: Theme.iconFont
                                                font.pixelSize: 13
                                            }

                                            ControlArea {
                                                id: eyeArea
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                Accessible.name: page.showPassword ? "Hide password" : "Show password"
                                                onClicked: page.showPassword = !page.showPassword
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: 76
                                        height: 34
                                        radius: Theme.radiusSm
                                        color: (page.connectingSsid === modelData.ssid) ? Theme.tint(Theme.accent, 0.4) : Theme.accent
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: (page.connectingSsid === modelData.ssid) ? "Joining…" : "Join"
                                            color: Theme.bg
                                            font.family: page.monoFont
                                            font.pixelSize: 12
                                            font.bold: true
                                        }

                                        ControlArea {
                                            anchors.fill: parent
                                            enabled: page.connectingSsid !== modelData.ssid
                                            cursorShape: Qt.PointingHandCursor
                                            Accessible.name: "Join " + modelData.ssid
                                            onClicked: page.connectSecured(modelData.ssid, pwField.text)
                                        }
                                    }

                                    Rectangle {
                                        width: 34
                                        height: 34
                                        radius: Theme.radiusSm
                                        color: Theme.tint("#ffffff", 0.04)
                                        border.width: 1
                                        border.color: Theme.border
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            anchors.centerIn: parent
                                            text: "×"
                                            color: Theme.textDim
                                            font.pixelSize: 16
                                        }

                                        ControlArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            Accessible.name: "Cancel"
                                            onClicked: {
                                                page.pendingSsid = "";
                                                page.pendingPassword = "";
                                                page.connectError = "";
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: page.connectError !== ""
                                    width: parent.width
                                    text: page.connectError
                                    color: Theme.danger
                                    font.family: page.monoFont
                                    font.pixelSize: 11
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }

                    Text {
                        visible: page.wifiEnabled && page.connectedNetworks.length > 0
                        width: parent.width
                        text: "CONNECTED NETWORK"
                        color: Theme.accent
                        font.family: page.monoFont
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 0
                    }

                    Repeater {
                        model: page.connectedNetworks
                        delegate: wifiCardDelegate
                    }

                    Item {
                        visible: page.wifiEnabled && page.connectedNetworks.length > 0 && page.availableNetworks.length > 0
                        width: parent.width
                        height: 6
                    }

                    Text {
                        visible: page.wifiEnabled && page.availableNetworks.length > 0
                        width: parent.width
                        text: "AVAILABLE NETWORKS"
                        color: Theme.textDim
                        font.family: page.monoFont
                        font.pixelSize: 10
                        font.bold: true
                        font.letterSpacing: 0
                    }

                    Repeater {
                        model: page.availableNetworks
                        delegate: wifiCardDelegate
                    }

                }

            }

        }

    }

}