import "../"
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Item {
    id: page

    property real marginLeft: 0
    property real marginRight: 55
    property real marginTop: 0
    property real marginBottom: 0

    property bool hasBattery: false
    property int batteryPercent: 100
    property string batteryStatus: "Connected"
    property bool isCharging: false
    property bool caffeineActive: false

    function refresh() {
        if (!pBattery.running)
            pBattery.running = true;
        if (!pCaffeine.running)
            pCaffeine.running = true;
    }

    function toggleCaffeine() {
        pCaffeineToggle.running = true;
    }

    function runCommand(cmd) {
        pCommand.command = ["sh", "-c", cmd];
        pCommand.running = true;
    }

    Component.onCompleted: page.refresh()

    Process {
        id: pBattery
        command: ["sh", "-c", "for b in /sys/class/power_supply/BAT*; do " +
                  "if [ -r \"$b/capacity\" ] && [ -r \"$b/status\" ]; then " +
                  "cat \"$b/capacity\"; cat \"$b/status\"; exit 0; fi; done; echo 'NONE'"]

        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().split("\n");
                if (lines[0] !== "NONE" && lines.length >= 2) {
                    var pct = parseInt(lines[0]);
                    if (!isNaN(pct)) {
                        page.hasBattery = true;
                        page.batteryPercent = Math.max(0, Math.min(100, pct));
                        page.batteryStatus = lines[1].trim();
                        page.isCharging = (lines[1].trim() === "Charging" || lines[1].trim() === "Full");
                        return;
                    }
                }
                page.hasBattery = false;
                page.batteryStatus = "AC Power";
                page.isCharging = true;
                page.batteryPercent = 100;
            }
        }
    }

    Process {
        id: pCaffeine
        command: ["sh", "-c", "if [ -x \"$MINIMAL_ROOT/scripts/caffeine.sh\" ]; then \"$MINIMAL_ROOT/scripts/caffeine.sh\" status 2>/dev/null; " +
                  "else echo '{\"class\":\"deactivated\"}'; fi"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var obj = JSON.parse(text.trim());
                    page.caffeineActive = (obj.class === "activated");
                } catch(e) {
                    page.caffeineActive = false;
                }
            }
        }
    }

    Process {
        id: pCaffeineToggle
        command: ["sh", "-c", "if [ -x \"$MINIMAL_ROOT/scripts/caffeine.sh\" ]; then \"$MINIMAL_ROOT/scripts/caffeine.sh\" toggle 2>/dev/null; fi"]
        onExited: {
            pCaffeine.running = true;
        }
    }

    Process {
        id: pCommand
        onExited: {
            page.refresh();
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: page.refresh()
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

        Column {
            id: content
            width: flick.width
            spacing: 14

            Text {
                text: "POWER & SLEEP"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 19
                font.letterSpacing: 3
                font.weight: Font.Bold
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }

            // Power Supply / Battery Card
            Rectangle {
                width: parent.width
                height: 104
                radius: Theme.radius
                color: Theme.tint("#ffffff", 0.03)
                border.width: 1
                border.color: Theme.border

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    Row {
                        width: parent.width
                        spacing: 10

                        Text {
                            text: page.hasBattery ? (page.isCharging ? "󱐋" : "󰁹") : "󰚥"
                            color: page.hasBattery ? (page.batteryPercent <= 15 ? Theme.danger : Theme.accent) : Theme.accent
                            font.family: Theme.iconFont
                            font.pixelSize: 18
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: page.hasBattery ? "BATTERY" : "AC POWER SOURCE"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            font.letterSpacing: 1.5
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Item {
                            width: 1
                            height: 1
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Rectangle {
                            height: 22
                            width: statusLabel.implicitWidth + 14
                            radius: 4
                            color: Theme.tint(page.isCharging ? Theme.accent : Theme.textDim, 0.12)
                            border.width: 1
                            border.color: Theme.tint(page.isCharging ? Theme.accent : Theme.textDim, 0.25)
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                id: statusLabel
                                anchors.centerIn: parent
                                text: page.hasBattery ? page.batteryStatus.toUpperCase() : "CONNECTED"
                                color: page.isCharging ? Theme.accent : Theme.textDim
                                font.family: Theme.monoFont
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 0.8
                            }
                        }

                        Item {
                            width: 1
                            height: 1
                            anchors.fill: parent
                            visible: false
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.hasBattery ? (page.batteryPercent + "%") : "100%"
                            color: page.hasBattery && page.batteryPercent <= 15 ? Theme.danger : Theme.text
                            font.family: Theme.monoFont
                            font.pixelSize: 16
                            font.weight: Font.Bold
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 6
                        radius: 3
                        color: Theme.alpha(Theme.textDim, 0.15)

                        Rectangle {
                            width: parent.width * Math.max(0.02, Math.min(1.0, (page.hasBattery ? page.batteryPercent : 100) / 100))
                            height: parent.height
                            radius: 3
                            color: page.hasBattery && page.batteryPercent <= 15 ? Theme.danger : (page.isCharging ? Theme.accent : Theme.accent2)

                            Behavior on width {
                                NumberAnimation { duration: Theme.animMed }
                            }
                        }
                    }

                    Text {
                        text: page.hasBattery ? (page.isCharging ? "Battery is charging from AC power" : "Running on battery power") : "Desktop workstation running on continuous AC power"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                }
            }

            // Caffeine / Keep Awake Card
            Rectangle {
                id: caffeineCard
                width: parent.width
                height: 76
                radius: Theme.radius
                color: page.caffeineActive ? Theme.tint(Theme.accent, 0.08) : Theme.tint("#ffffff", 0.03)
                border.width: 1
                border.color: page.caffeineActive ? Theme.accent : Theme.border

                Behavior on color {
                    ColorAnimation { duration: Theme.animFast }
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.right: caffeineSwitch.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Rectangle {
                        width: 40
                        height: 40
                        radius: Theme.radiusSm
                        color: page.caffeineActive ? Theme.tint(Theme.accent, 0.2) : Theme.tint("#ffffff", 0.06)
                        border.width: 1
                        border.color: page.caffeineActive ? Theme.accent : Theme.border
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: page.caffeineActive ? "󰅶" : "󰛊"
                            font.family: Theme.iconFont
                            font.pixelSize: 20
                            color: page.caffeineActive ? Theme.accent : Theme.textDim
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Row {
                            spacing: 8
                            Text {
                                text: "Keep Screen Awake (Caffeine)"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                font.weight: Font.Bold
                            }

                            Rectangle {
                                width: 44
                                height: 18
                                radius: 4
                                color: page.caffeineActive ? Theme.tint(Theme.accent, 0.15) : Theme.tint("#ffffff", 0.06)
                                border.width: 1
                                border.color: page.caffeineActive ? Theme.accent : Theme.border
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: page.caffeineActive ? "ACTIVE" : "OFF"
                                    color: page.caffeineActive ? Theme.accent : Theme.textFaint
                                    font.family: Theme.monoFont
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                }
                            }
                        }

                        Text {
                            text: page.caffeineActive ? "Display lock and system sleep are blocked while active" : "Allows normal screen timeout, blanking, and idle sleep"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                        }
                    }
                }

                // Switch Toggle
                Rectangle {
                    id: caffeineSwitch
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 48
                    height: 26
                    radius: 13
                    color: page.caffeineActive ? Theme.accent : Theme.tint("#ffffff", 0.1)
                    border.width: 1
                    border.color: page.caffeineActive ? Theme.accent : Theme.borderStrong

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast }
                    }

                    Rectangle {
                        id: switchThumb
                        width: 20
                        height: 20
                        radius: 10
                        color: page.caffeineActive ? "#ffffff" : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                        x: page.caffeineActive ? parent.width - width - 3 : 3

                        Behavior on x {
                            NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onEntered: {
                        if (!page.caffeineActive) caffeineCard.color = Theme.tint("#ffffff", 0.05);
                    }
                    onExited: {
                        if (!page.caffeineActive) caffeineCard.color = Theme.tint("#ffffff", 0.03);
                    }
                    onClicked: page.toggleCaffeine()
                }
            }

            // Quick Tools & Modes
            Text {
                text: "MODES & PERFORMANCE"
                color: Theme.text
                topPadding: 6
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.bold: true
                font.letterSpacing: 2
            }

            Repeater {
                model: [{
                    "icon": "󰊴",
                    "label": "Gamemode / Ultra Performance",
                    "desc": "Disable blur, animations, and shadows for pure gaming & render performance",
                    "action": "TOGGLE",
                    "command": "bash -c 'if [ -x \"$MINIMAL_ROOT/scripts/gamemode.sh\" ]; then \"$MINIMAL_ROOT/scripts/gamemode.sh\"; notify-send \"Gamemode\" \"Toggled visual effects mode\"; fi'"
                }, {
                    "icon": "󰖔",
                    "label": "Night Light (Blue Filter)",
                    "desc": "Warm display color temperature to eliminate blue light and reduce eye strain",
                    "action": "TOGGLE",
                    "command": "bash -c 'if [ -x \"$MINIMAL_ROOT/scripts/night-light.sh\" ]; then \"$MINIMAL_ROOT/scripts/night-light.sh\"; notify-send \"Night Light\" \"Toggled color temperature\"; fi'"
                }]

                delegate: Rectangle {
                    id: modeRoot
                    required property var modelData

                    width: content.width
                    height: 52
                    radius: Theme.radius
                    color: Theme.tint("#ffffff", 0.03)
                    border.width: 1
                    border.color: Theme.border

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: modePill.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        Text {
                            text: modeRoot.modelData.icon
                            color: Theme.accent
                            font.family: Theme.iconFont
                            font.pixelSize: 18
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: modeRoot.modelData.label
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }

                            Text {
                                text: modeRoot.modelData.desc
                                color: Theme.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }
                    }

                    Rectangle {
                        id: modePill
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 72
                        height: 28
                        radius: Theme.radiusSm
                        color: Theme.tint(Theme.accent, 0.12)
                        border.width: 1
                        border.color: Theme.tint(Theme.accent, 0.3)

                        Text {
                            anchors.centerIn: parent
                            text: modeRoot.modelData.action
                            color: Theme.accent
                            font.family: Theme.monoFont
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 0.8
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            parent.color = Theme.tint(Theme.accent, 0.08);
                            parent.border.color = Theme.accent;
                        }
                        onExited: {
                            parent.color = Theme.tint("#ffffff", 0.03);
                            parent.border.color = Theme.border;
                        }
                        onClicked: page.runCommand(modeRoot.modelData.command)
                    }
                }
            }

            // Session & Power Actions
            Text {
                text: "SESSION & POWER ACTIONS"
                color: Theme.text
                topPadding: 6
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.bold: true
                font.letterSpacing: 2
            }

            Repeater {
                model: [{
                    "icon": "󰌾",
                    "label": "Lock Session",
                    "desc": "Lock the current session immediately",
                    "action": "LOCK",
                    "command": "bash -c 'if [ -x \"$MINIMAL_ROOT/scripts/lock.sh\" ]; then \"$MINIMAL_ROOT/scripts/lock.sh\"; else hyprlock; fi'"
                }, {
                    "icon": "󰒲",
                    "label": "Suspend System",
                    "desc": "Put the machine into low-power sleep mode",
                    "action": "SLEEP",
                    "command": "systemctl suspend"
                }, {
                    "icon": "",
                    "label": "Open Power Menu",
                    "desc": "Shutdown, restart, hibernate, or log out",
                    "action": "POWER",
                    "command": "bash -c 'if [ -x \"$MINIMAL_ROOT/scripts/powermenu.sh\" ]; then \"$MINIMAL_ROOT/scripts/powermenu.sh\"; fi'"
                }]

                delegate: Rectangle {
                    id: actionRoot
                    required property var modelData

                    width: content.width
                    height: 52
                    radius: Theme.radius
                    color: Theme.tint("#ffffff", 0.03)
                    border.width: 1
                    border.color: Theme.border

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: actPill.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        Text {
                            text: actionRoot.modelData.icon
                            color: Theme.accent
                            font.family: Theme.iconFont
                            font.pixelSize: 18
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: actionRoot.modelData.label
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }

                            Text {
                                text: actionRoot.modelData.desc
                                color: Theme.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                            }
                        }
                    }

                    Rectangle {
                        id: actPill
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 72
                        height: 28
                        radius: Theme.radiusSm
                        color: Theme.tint(Theme.accent, 0.12)
                        border.width: 1
                        border.color: Theme.tint(Theme.accent, 0.3)

                        Text {
                            anchors.centerIn: parent
                            text: actionRoot.modelData.action
                            color: Theme.accent
                            font.family: Theme.monoFont
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 0.8
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            parent.color = Theme.tint(Theme.accent, 0.08);
                            parent.border.color = Theme.accent;
                        }
                        onExited: {
                            parent.color = Theme.tint("#ffffff", 0.03);
                            parent.border.color = Theme.border;
                        }
                        onClicked: page.runCommand(actionRoot.modelData.command)
                    }
                }
            }
        }

        ScrollBar.vertical: ScrollBar {
            id: scrollBar
            background: Rectangle { color: "transparent"; radius: width / 2 }
            contentItem: Rectangle { color: Theme.accent; radius: width / 2 }
        }
    }
}
