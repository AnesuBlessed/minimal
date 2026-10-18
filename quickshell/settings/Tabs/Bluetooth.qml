import "../"
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

Item {
    id: page

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter ? adapter.enabled : false
    readonly property bool scanning: adapter ? adapter.discovering : false
    readonly property bool discoverable: adapter ? adapter.discoverable : false

    property string statusText: ""
    property real marginLeft: 0
    property real marginRight: 12
    property real marginTop: 0
    property real marginBottom: 0
    property bool manualOff: false
    property int deviceStateRevision: 0
    property string localAddress: ""
    property string localName: adapter ? (adapter.name || "cachyos-x8664") : "cachyos-x8664"

    function refreshLocalInfo() {
        pLocalInfo.running = true
    }

    function sendFile(address, name) {
        page.setStatus("Opening file transfer to " + (name || address || "device") + "...")
        var scriptPath = (Quickshell.env("MINIMAL_ROOT") || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/minimal")) + "/scripts/bluetooth-send.py";
        if (address) {
            Quickshell.execDetached(["python3", scriptPath, address])
        } else {
            Quickshell.execDetached(["python3", scriptPath])
        }
    }

    readonly property bool hasConnected: {
        var rev = deviceStateRevision;
        if (!page.adapter || !page.adapter.devices) return false;
        var vals = page.adapter.devices.values;
        if (!vals) return false;
        for (var i = 0; i < vals.length; i++) {
            if (vals[i] && (vals[i].connected || vals[i].state === BluetoothDeviceState.Connected))
                return true;
        }
        return false;
    }

    readonly property bool hasAvailable: {
        var rev = deviceStateRevision;
        if (!page.adapter || !page.adapter.devices) return false;
        var vals = page.adapter.devices.values;
        if (!vals) return false;
        for (var i = 0; i < vals.length; i++) {
            if (vals[i] && !(vals[i].connected || vals[i].state === BluetoothDeviceState.Connected))
                return true;
        }
        return false;
    }

    function setStatus(text) {
        page.statusText = text

        if (text !== "")
            statusTimer.restart()
        else
            statusTimer.stop()
    }

    function setDiscovering(on) {
        if (!page.adapter || !page.powered)
            return

        // Never aggressively scan when devices are connected to prevent packet loss & disconnects
        if (on && page.hasConnected)
            return

        page.adapter.discovering = Boolean(on)
    }

    function toggleDiscoverable() {
        if (!page.adapter || !page.powered) return;
        var next = !page.adapter.discoverable;
        Quickshell.execDetached(["bluetoothctl", "discoverable-timeout", "0"]);
        Quickshell.execDetached(["bluetoothctl", "pairable", "on"]);
        Quickshell.execDetached(["bluetoothctl", "discoverable", next ? "on" : "off"]);
        page.adapter.discoverable = next;
        page.setStatus(next ? "Device is now always discoverable" : "Device is hidden from discovery");
    }

    function togglePower() {
        Quickshell.execDetached(["rfkill", "unblock", "bluetooth"]);
        if (!page.adapter) {
            page.setStatus("Unblocking Bluetooth radio and initializing...")
            return
        }

        if (page.adapter.enabled) {
            page.manualOff = true
            page.setDiscovering(false)
            page.adapter.enabled = false
            page.setStatus("Bluetooth off")
            return
        }

        page.manualOff = false
        page.adapter.enabled = true
        Quickshell.execDetached(["bluetoothctl", "discoverable-timeout", "0"]);
        Quickshell.execDetached(["bluetoothctl", "pairable", "on"]);
        Quickshell.execDetached(["bluetoothctl", "discoverable", "on"]);
        page.setStatus("Turning Bluetooth on (Discoverable)...")
    }

    function deviceDisplayName(dev) {
        if (!dev)
            return "Bluetooth Device"
        var candidate = (dev.name || dev.deviceName || dev.alias || "").trim()
        var isCode = !candidate ||
                     /^([0-9A-Fa-f]{2}[:_-]){5}([0-9A-Fa-f]{2})$/i.test(candidate) ||
                     /^dev[_-][0-9A-Za-z_:]+$/i.test(candidate) ||
                     /^[0-9A-Fa-f]{12}$/i.test(candidate) ||
                     /^bluez_/i.test(candidate)
        return isCode ? "Bluetooth Device" : candidate
    }

    function deviceAction(dev, deviceCard) {
        if (!dev)
            return

        var name = page.deviceDisplayName(dev)
        var address = dev.address

        if (dev.connected || dev.state === BluetoothDeviceState.Connected) {
            page.setStatus("Disconnecting " + name + "...")
            disconnectProcess.command = ["bluetoothctl", "disconnect", address]
            disconnectProcess.running = true
            return
        }

        page.setDiscovering(false)
        page.setStatus("Connecting to " + name + "...")
        connectProcess.command = ["sh", "-c", "bluetoothctl discoverable-timeout 0; bluetoothctl pairable on; if ! bluetoothctl info '" + address + "' | grep -q 'Paired: yes'; then bluetoothctl pair '" + address + "'; fi && bluetoothctl trust '" + address + "' && bluetoothctl connect '" + address + "'"]
        connectProcess.running = true
    }

    Process {
        id: connectProcess
        running: false
        onExited: (exitCode) => {
            if (exitCode === 0) {
                page.setStatus("Connected successfully!")
            } else {
                page.setStatus("Connection failed. Check device.")
            }
        }
    }

    Process {
        id: disconnectProcess
        running: false
    }

    Process {
        id: pResetAdapter
        command: ["sh", "-c", "rfkill unblock bluetooth 2>/dev/null; bluetoothctl power off 2>/dev/null; sleep 0.5; bluetoothctl power on 2>/dev/null; notify-send 'Bluetooth' 'Adapter reset successfully'"]
        onExited: {
            page.setStatus("Adapter reset complete");
            page.setDiscovering(page.visible && page.powered);
            page.refreshLocalInfo();
        }
    }

    Process {
        id: pLocalInfo
        command: ["sh", "-c", "bluetoothctl show | awk '/Controller/ {mac=$2} /Alias:/ {alias=$2} /Name:/ {if(!alias) alias=$2} END {print mac \",\" (alias ? alias : \"minimal\")}'"]
        stdout: SplitParser {
            onRead: (line) => {
                var trimmed = line.trim()
                var parts = trimmed.split(",")
                if (parts.length >= 1 && parts[0]) {
                    page.localAddress = parts[0].trim()
                }
                if (parts.length >= 2 && parts[1]) {
                    page.localName = parts[1].trim()
                }
            }
        }
    }

    function removeDevice(dev) {
        if (!dev)
            return

        var address = dev.address
        if (address) {
            disconnectProcess.command = ["bluetoothctl", "remove", address]
            disconnectProcess.running = true
        }

        if (
            dev.connected ||
            dev.state === BluetoothDeviceState.Connected ||
            dev.state === BluetoothDeviceState.Connecting ||
            dev.state === BluetoothDeviceState.Disconnecting
        ) {
            dev.disconnect()
        }

        if (typeof dev.forget === "function") {
            dev.forget()
        }
    }

    function actionLabel(dev) {
        if (!dev)
            return ""

        if (dev.pairing)
            return "PAIRING..."

        if (dev.connected || dev.state === BluetoothDeviceState.Connected)
            return "DISCONNECT"

        switch (dev.state) {
        case BluetoothDeviceState.Connecting:
            return "CONNECTING..."

        case BluetoothDeviceState.Disconnecting:
            return "DISCONNECTING..."

        default:
            return dev.paired ? "CONNECT" : "PAIR"
        }
    }

    onAdapterChanged: {
        page.setDiscovering(page.visible && page.powered)
    }

    onVisibleChanged: {
        if (page.visible) {
            page.setDiscovering(page.visible && page.powered)
            page.setDiscovering(page.powered)
        } else {
            page.setDiscovering(false)
        }
    }

    onPoweredChanged: {
        if (page.powered) {
            page.setDiscovering(page.visible)
            page.refreshLocalInfo()
        } else {
            page.setDiscovering(false)
        }
    }

    Component.onCompleted: {
        page.setDiscovering(page.visible && page.powered)
        page.refreshLocalInfo()
    }

    Component.onDestruction: {
        page.setDiscovering(false)
    }

    Timer {
        id: statusTimer
        interval: 3500
        onTriggered: {
            page.statusText = ""
        }
    }

    Connections {
        target: page.adapter

        function onEnabledChanged() {
            if (page.adapter && page.adapter.enabled) {
                page.setStatus("Bluetooth on")
                page.setDiscovering(page.visible)
            } else {
                page.setDiscovering(false)
            }
        }
    }

    Timer {
        id: discoveryRetryTimer
        interval: 8000
        repeat: true
        running: page.visible && page.powered &&
                 page.adapter &&
                 page.adapter.enabled &&
                 !page.hasConnected

        onTriggered: {
            if (
                page.adapter &&
                page.powered &&
                !page.hasConnected &&
                !page.adapter.discovering
            ) {
                page.adapter.discovering = true
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

        Row {
            width: parent.width
            spacing: 8

            Rectangle {
                width: (parent.width - 16) / 3
                height: 36
                radius: Theme.radius

                color: page.powered
                       ? Theme.alpha(Theme.accent, 0.1)
                       : Theme.alpha(Theme.textFaint, 0.15)

                border.width: 1
                border.color: page.powered
                              ? Theme.accent
                              : Theme.textFaint

                Text {
                    anchors.centerIn: parent

                    text: {
                        if (!page.adapter)
                            return "NO ADAPTER"

                        return page.powered
                               ? "BLUETOOTH ON"
                               : "BLUETOOTH OFF"
                    }

                    color: page.powered
                           ? Theme.accent
                           : Theme.textFaint

                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fontSecondary
                    font.bold: true
                    font.letterSpacing: 0
                }

                ControlArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        page.togglePower()
                    }
                }
            }

            Rectangle {
                width: (parent.width - 16) / 3
                height: 36
                radius: Theme.radius
                opacity: page.powered ? 1.0 : 0.45

                color: (page.powered && page.discoverable)
                       ? Theme.alpha(Theme.accent, 0.12)
                       : Theme.alpha(Theme.textFaint, 0.15)

                border.width: 1
                border.color: (page.powered && page.discoverable)
                              ? Theme.accent
                              : Theme.textFaint

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: (page.powered && page.discoverable) ? "󰂯" : "󰂲"
                        font.family: Theme.iconFont
                        font.pixelSize: 13
                        color: (page.powered && page.discoverable)
                               ? Theme.accent
                               : Theme.textFaint
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: (page.powered && page.discoverable)
                              ? "DISCOVERABLE"
                              : "HIDDEN"

                        color: (page.powered && page.discoverable)
                               ? Theme.accent
                               : Theme.textFaint

                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fontSecondary
                        font.bold: true
                        font.letterSpacing: 0
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ControlArea {
                    anchors.fill: parent
                    cursorShape: page.powered ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (page.powered)
                            page.toggleDiscoverable()
                    }
                }
            }

            Rectangle {
                width: (parent.width - 16) / 3
                height: 36
                radius: Theme.radius
                color: Theme.tint(Theme.accent, 0.08)
                border.width: 1
                border.color: Theme.tint(Theme.accent, 0.25)

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "󰑓"
                        font.family: Theme.iconFont
                        font.pixelSize: 13
                        color: Theme.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "RESET"
                        color: Theme.accent
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fontSecondary
                        font.bold: true
                        font.letterSpacing: 0
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ControlArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onEntered: parent.color = Theme.tint(Theme.accent, 0.15)
                    onExited: parent.color = Theme.tint(Theme.accent, 0.08)
                    onClicked: {
                        page.setStatus("Resetting Bluetooth adapter...");
                        pResetAdapter.running = true;
                    }
                }
            }
        }

        Text {
            width: parent.width
            visible: page.statusText !== ""
            text: page.statusText
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSecondary
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            visible: !page.adapter
            text: "Waiting for Bluetooth service and adapter..."
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSecondary
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }

        // Local PC Bluetooth Information Banner
        Rectangle {
            id: pcBanner
            width: parent.width
            height: 56
            radius: Theme.radius
            visible: page.powered
            color: Theme.alpha(Theme.surfaceColor, 0.45)
            border.width: 1
            border.color: Theme.alpha(Theme.accent, 0.25)

            // Right-anchored Send File Button
            Rectangle {
                id: sendBtn
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 96
                height: 30
                radius: Theme.radiusSm
                color: Theme.alpha(Theme.accent, 0.15)
                border.width: 1
                border.color: Theme.accent

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text: "󰈔"
                        font.family: Theme.iconFont
                        font.pixelSize: 13
                        color: Theme.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Send File"
                        color: Theme.accent
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fontSecondary
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ControlArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onEntered: parent.color = Theme.alpha(Theme.accent, 0.28)
                    onExited: parent.color = Theme.alpha(Theme.accent, 0.15)
                    onClicked: page.sendFile("", "")
                }
            }

            // Left-anchored and constrained content area (never overlaps sendBtn)
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: sendBtn.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Text {
                    text: "󰌢"
                    font.family: Theme.iconFont
                    font.pixelSize: 22
                    color: Theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    width: Math.max(0, parent.width - 32)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            text: page.localName || "minimal"
                            color: Theme.text
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fontTitle
                            font.bold: true
                            width: Math.min(implicitWidth, Math.max(40, parent.width - (page.localAddress !== "" ? (addrText.implicitWidth + 8) : 0)))
                            elide: Text.ElideRight
                        }

                        Text {
                            id: addrText
                            visible: page.localAddress !== ""
                            text: "(" + page.localAddress + ")"
                            color: Theme.accent
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fontSecondary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        width: parent.width
                        text: (page.discoverable
                              ? "Discoverable: visible to nearby devices"
                              : "Hidden from nearby devices") + (page.hasConnected ? " · Protected" : "")
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Flickable {
            id: flick
            width: parent.width
            height: Math.max(0, parent.height - y)
            clip: true
            contentWidth: width
            contentHeight: list.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: list
                width: Math.max(0, flick.width - 10)
                spacing: 6

                Item {
                    width: list.width
                    height: 100
                    visible: page.adapter && !page.powered

                    Column {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "\uf294"
                            color: Theme.textDim
                            font.family: Theme.iconFont
                            font.pixelSize: 24
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Bluetooth is off"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSecondary
                            font.letterSpacing: 0
                        }
                    }
                }

                Item {
                    width: list.width
                    height: 112
                    visible: page.powered && !page.hasConnected && !page.hasAvailable

                    Column {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.scanning ? "\uf1eb" : "\uf071"
                            color: Theme.textDim
                            font.family: Theme.iconFont
                            font.pixelSize: 22
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.scanning
                                  ? "SCANNING FOR DEVICES..."
                                  : "NO DEVICES FOUND"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSecondary
                            font.letterSpacing: 0
                        }

                        Text {
                            width: list.width - 20
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.scanning
                                  ? "Make your device discoverable and keep this page open."
                                  : "Waiting for Bluetooth discovery..."
                            color: Theme.textFaint
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSecondary
                            wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    ControlArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.setDiscovering(true)
                    }
                }

                Component {
                    id: deviceCardComponent

                    Rectangle {
                        id: card

                        readonly property BluetoothDevice device: parent.deviceModel
                        property bool connectAfterPair: false
                        readonly property bool isConnected:
                            device ? (device.connected || device.state === BluetoothDeviceState.Connected) : false

                        anchors.fill: parent
                        radius: Theme.radius

                        color: isConnected
                               ? Theme.alpha(Theme.accent, 0.1)
                               : "transparent"

                        border.width: 1
                        border.color: isConnected
                                      ? Theme.accent
                                      : Theme.border

                        Connections {
                            target: card.device

                            function onPairedChanged() {
                                page.deviceStateRevision++
                                if (
                                    card.device &&
                                    card.device.paired &&
                                    card.connectAfterPair
                                ) {
                                    card.connectAfterPair = false
                                    card.device.trusted = true

                                    page.setStatus(
                                        "Connecting to " +
                                        page.deviceDisplayName(card.device) + "..."
                                    )

                                    connectProcess.command = ["bluetoothctl", "connect", card.device.address]
                                    connectProcess.running = true
                                }
                            }

                            function onConnectedChanged() {
                                page.deviceStateRevision++
                                if (card.device && card.device.connected) {
                                    page.setStatus(
                                        "Connected to " +
                                        page.deviceDisplayName(card.device)
                                    )
                                }
                            }

                            function onStateChanged() {
                                page.deviceStateRevision++
                                if (
                                    card.device &&
                                    (card.device.connected ||
                                     card.device.state === BluetoothDeviceState.Connected)
                                ) {
                                    page.setStatus(
                                        "Connected to " +
                                        page.deviceDisplayName(card.device)
                                    )
                                }
                            }

                            function onPairingChanged() {
                                if (
                                    card.device &&
                                    !card.device.pairing &&
                                    !card.device.paired &&
                                    card.connectAfterPair
                                ) {
                                    card.connectAfterPair = false
                                    page.setStatus("Pairing failed. Check Bluetooth permissions.")
                                }
                            }
                        }

                        Item {
                            id: actionArea
                            x: card.width - width - 14
                            y: 0
                            width: 175
                            height: card.height

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                height: 30
                                spacing: 10

                                Rectangle {
                                    id: actionButton
                                    width: Math.max(76, actionText.implicitWidth + 16)
                                    height: 28
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: Theme.radiusSm
                                    color: actionMa.containsMouse
                                           ? (card.isConnected ? Theme.alpha(Theme.danger, 0.22) : Theme.alpha(Theme.accent, 0.22))
                                           : (card.isConnected ? Theme.alpha(Theme.danger, 0.12) : Theme.alpha(Theme.accent, 0.12))
                                    border.width: 1
                                    border.color: card.isConnected ? Theme.danger : Theme.accent

                                    Text {
                                        id: actionText
                                        anchors.centerIn: parent
                                        text: page.actionLabel(card.device)
                                        color: card.isConnected
                                               ? Theme.danger
                                               : Theme.accent
                                        font.family: Theme.monoFont
                                        font.pixelSize: Theme.fontSecondary
                                        font.bold: true
                                        font.letterSpacing: 0
                                    }

                                    ControlArea {
                                        id: actionMa
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onClicked: {
                                            page.deviceAction(
                                                card.device,
                                                card
                                            )
                                        }
                                    }
                                }

                                Item {
                                    id: sendFileButton
                                    visible: card.device && (card.device.paired || card.isConnected)
                                    width: 28
                                    height: 28
                                    anchors.verticalCenter: parent.verticalCenter

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Theme.radiusSm
                                        color: sendMouseArea.containsMouse ? Theme.alpha(Theme.accent, 0.2) : "transparent"
                                        border.width: 1
                                        border.color: sendMouseArea.containsMouse ? Theme.accent : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰈔"
                                            color: Theme.accent
                                            font.family: Theme.iconFont
                                            font.pixelSize: 15
                                        }
                                    }

                                    ControlArea {
                                        id: sendMouseArea
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onClicked: {
                                            page.sendFile(card.device.address, page.deviceDisplayName(card.device))
                                        }
                                    }

                                    Rectangle {
                                        visible: sendMouseArea.containsMouse
                                        z: 100
                                        x: -16
                                        y: sendFileButton.height + 6
                                        width: sendTooltipText.width + 16
                                        height: 24
                                        radius: 4
                                        color: Theme.alpha(Theme.baseColor, 0.95)
                                        border.width: 1
                                        border.color: Theme.border

                                        Text {
                                            id: sendTooltipText
                                            anchors.centerIn: parent
                                            text: "Send File"
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSecondary
                                        }
                                    }
                                }

                                Item {
                                    id: removeButton
                                    width: 28
                                    height: 28
                                    anchors.verticalCenter: parent.verticalCenter

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Theme.radiusSm
                                        color: unpairMouseArea.containsMouse ? Theme.alpha(Theme.danger, 0.2) : "transparent"
                                        border.width: 1
                                        border.color: unpairMouseArea.containsMouse ? Theme.danger : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "\uf293"
                                            color: unpairMouseArea.containsMouse ? Theme.danger : Theme.textDim
                                            font.family: Theme.iconFont
                                            font.pixelSize: 16
                                        }
                                    }

                                    ControlArea {
                                        id: unpairMouseArea
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onClicked: {
                                            page.removeDevice(card.device)
                                        }
                                    }

                                    Rectangle {
                                        visible: unpairMouseArea.containsMouse
                                        z: 100
                                        x: -8
                                        y: removeButton.height + 6
                                        width: tooltipText.width + 16
                                        height: 24
                                        radius: 4
                                        color: Theme.alpha(Theme.baseColor, 0.95)
                                        border.width: 1
                                        border.color: Theme.border

                                        Text {
                                            id: tooltipText
                                            anchors.centerIn: parent
                                            text: "Unpair"
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSecondary
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            id: deviceInfo
                            x: 14
                            y: 0
                            width: Math.max(
                                0,
                                card.width - actionArea.width - 42
                            )
                            height: card.height

                            Text {
                                id: deviceIcon
                                x: 0
                                y: (parent.height - height) / 2
                                width: 18
                                height: 18
                                text: "\uf294"
                                color: card.isConnected
                                       ? Theme.accent
                                       : Theme.textDim
                                font.family: Theme.iconFont
                                font.pixelSize: 15
                                verticalAlignment: Text.AlignVCenter
                            }

                            Column {
                                id: deviceText
                                x: 28
                                y: (parent.height - height) / 2
                                width: Math.max(0, parent.width - x)
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: page.deviceDisplayName(card.device)
                                    elide: Text.ElideRight
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                }

                                Text {
                                    width: parent.width
                                    text: {
                                        if (!card.device) return ""
                                        var parts = []

                                        if (card.isConnected)
                                            parts.push("Connected")
                                        else if (card.device.paired)
                                            parts.push("Paired")
                                        else
                                            parts.push("Available")

                                        if (card.device.batteryAvailable) {
                                            parts.push(
                                                Math.round(
                                                    card.device.battery * 100
                                                ) + "%"
                                            )
                                        }

                                        if (card.device.address) {
                                            parts.push(card.device.address)
                                        }

                                        return parts.join("  •  ")
                                    }
                                    color: card.isConnected
                                           ? Theme.accent
                                           : Theme.textFaint
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSecondary
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: page.hasConnected
                    width: parent.width
                    text: "CONNECTED DEVICES"
                    color: Theme.accent
                    font.family: Theme.monoFont
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 0
                }

                Repeater {
                    id: connectedRepeater
                    model: page.adapter && page.powered ? page.adapter.devices : null
                    delegate: Item {
                        required property BluetoothDevice modelData
                        readonly property bool isConnected: modelData.connected || modelData.state === BluetoothDeviceState.Connected
                        visible: isConnected
                        width: list.width
                        height: isConnected ? 52 : 0

                        Loader {
                            anchors.fill: parent
                            property BluetoothDevice deviceModel: modelData
                            active: parent.isConnected
                            sourceComponent: deviceCardComponent
                        }
                    }
                }

                Item {
                    visible: page.hasConnected && page.hasAvailable
                    width: parent.width
                    height: 6
                }

                Text {
                    visible: page.hasAvailable
                    width: parent.width
                    text: "AVAILABLE DEVICES"
                    color: Theme.textDim
                    font.family: Theme.monoFont
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 0
                }

                Repeater {
                    id: availableRepeater
                    model: page.adapter && page.powered ? page.adapter.devices : null
                    delegate: Item {
                        required property BluetoothDevice modelData
                        readonly property bool isConnected: modelData.connected || modelData.state === BluetoothDeviceState.Connected
                        visible: !isConnected
                        width: list.width
                        height: !isConnected ? 52 : 0

                        Loader {
                            anchors.fill: parent
                            property BluetoothDevice deviceModel: modelData
                            active: !parent.isConnected
                            sourceComponent: deviceCardComponent
                        }
                    }
                }
            }
        }
    }
}