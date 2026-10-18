import "../"
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Item {
    id: page

    property real marginLeft: 0
    property real marginRight: 12
    property real marginTop: 0
    property real marginBottom: 0

    property bool hasBattery: false
    property int batteryPercent: 100
    property string batteryStatus: "Connected"
    property bool isCharging: false
    property bool caffeineActive: false
    property string activePowerProfile: "balanced"
    property int idleBlankSec: 330
    property int idleSleepSec: 1800

    function refresh() {
        if (!pBattery.running) pBattery.running = true;
        if (!pCaffeine.running) pCaffeine.running = true;
        if (!pProfileGet.running) pProfileGet.running = true;
        if (!pIdleGet.running) pIdleGet.running = true;
    }

    function toggleCaffeine() {
        page.caffeineActive = !page.caffeineActive;
        pCaffeineToggle.running = true;
    }

    function setPowerProfile(profile) {
        page.activePowerProfile = profile;
        pProfileSet.command = ["powerprofilesctl", "set", profile];
        pProfileSet.running = true;
    }

    function setBlankTimeout(sec) {
        page.idleBlankSec = sec;
        pIdleSet.command = ["sh", "-c", "\"$MINIMAL_ROOT/scripts/idle-config.sh\" set-blank " + sec];
        pIdleSet.running = true;
    }

    function setSleepTimeout(sec) {
        page.idleSleepSec = sec;
        pIdleSet.command = ["sh", "-c", "\"$MINIMAL_ROOT/scripts/idle-config.sh\" set-sleep " + sec];
        pIdleSet.running = true;
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
        id: pProfileGet
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                var p = text.trim();
                if (p) page.activePowerProfile = p;
            }
        }
    }

    Process {
        id: pProfileSet
        onExited: pProfileGet.running = true
    }

    Process {
        id: pIdleGet
        command: ["sh", "-c", "if [ -x \"$MINIMAL_ROOT/scripts/idle-config.sh\" ]; then \"$MINIMAL_ROOT/scripts/idle-config.sh\" status; else echo '{\"blank\":300,\"sleep\":1800}'; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var obj = JSON.parse(text.trim());
                    page.idleBlankSec = obj.blank !== undefined ? obj.blank : 300;
                    page.idleSleepSec = obj.sleep !== undefined ? obj.sleep : 1800;
                } catch(e) {}
            }
        }
    }

    Process {
        id: pIdleSet
        onExited: pIdleGet.running = true
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
        onExited: page.refresh()
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
            width: Math.max(0, flick.width - 10)
            spacing: 14

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

                    Item {
                        width: parent.width
                        height: 24

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
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
                                font.letterSpacing: 0
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
                                    text: page.hasBattery ? page.batteryStatus : "CONNECTED"
                                    color: page.isCharging ? Theme.accent : Theme.textDim
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fontSecondary
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0
                                }
                            }
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
                        text: page.hasBattery ? (page.isCharging ? "Battery is charging from AC power" : "Running on battery power") : "Workstation running on continuous AC power"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSecondary
                    }
                }
            }

            // Power Profile Selector
            Text {
                text: "Power profile"
                color: Theme.text
                topPadding: 4
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
                font.letterSpacing: 0
            }

            Row {
                width: parent.width
                spacing: 8

                Repeater {
                    model: [
                        { "id": "performance", "label": "PERFORMANCE", "icon": "󰓅", "desc": "Maximum CPU clock & responsive governors" },
                        { "id": "balanced", "label": "BALANCED", "icon": "󰾆", "desc": "Dynamic scaling for work & everyday use" },
                        { "id": "power-saver", "label": "POWER SAVER", "icon": "󰌪", "desc": "Limits frequencies to preserve battery" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        property bool active: page.activePowerProfile === modelData.id
                        width: (parent.width - 16) / 3
                        height: 54
                        radius: Theme.radius
                        color: active ? Theme.alpha(Theme.accent, 0.12) : Theme.tint("#ffffff", 0.03)
                        border.width: 1
                        border.color: active ? Theme.borderAccent : Theme.border

                        Column {
                            anchors.centerIn: parent
                            spacing: 3

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 6

                                Text {
                                    text: modelData.icon
                                    color: active ? Theme.accent : Theme.textDim
                                    font.family: Theme.iconFont
                                    font.pixelSize: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: modelData.label
                                    color: active ? Theme.accent : Theme.text
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fontSecondary
                                    font.bold: true
                                    font.letterSpacing: 0
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
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
                            onClicked: page.setPowerProfile(modelData.id)
                        }
                    }
                }
            }

            // Screen Blanking / Idle Timeout
            Text {
                text: "Screen blank timeout"
                color: Theme.text
                topPadding: 4
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
                font.letterSpacing: 0
            }

            Row {
                width: parent.width
                spacing: 6

                Repeater {
                    model: [
                        { "sec": 180, "label": "3M" },
                        { "sec": 300, "label": "5M" },
                        { "sec": 600, "label": "10M" },
                        { "sec": 900, "label": "15M" },
                        { "sec": 1800, "label": "30M" },
                        { "sec": 0, "label": "NEVER" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        property bool active: page.idleBlankSec === modelData.sec
                        width: (parent.width - 30) / 6
                        height: 32
                        radius: Theme.radiusSm
                        color: active ? Theme.alpha(Theme.accent, 0.15) : Theme.tint("#ffffff", 0.04)
                        border.width: 1
                        border.color: active ? Theme.borderAccent : Theme.border

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: active ? Theme.accent : Theme.textDim
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fontSecondary
                            font.bold: true
                        }

                        ControlArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.setBlankTimeout(modelData.sec)
                        }
                    }
                }
            }

            // System Sleep Timeout
            Text {
                text: "System sleep timeout"
                color: Theme.text
                topPadding: 4
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
                font.letterSpacing: 0
            }

            Row {
                width: parent.width
                spacing: 6

                Repeater {
                    model: [
                        { "sec": 900, "label": "15M" },
                        { "sec": 1800, "label": "30M" },
                        { "sec": 3600, "label": "1H" },
                        { "sec": 7200, "label": "2H" },
                        { "sec": 0, "label": "NEVER" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        property bool active: page.idleSleepSec === modelData.sec
                        width: (parent.width - 24) / 5
                        height: 32
                        radius: Theme.radiusSm
                        color: active ? Theme.alpha(Theme.accent, 0.15) : Theme.tint("#ffffff", 0.04)
                        border.width: 1
                        border.color: active ? Theme.borderAccent : Theme.border

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: active ? Theme.accent : Theme.textDim
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fontSecondary
                            font.bold: true
                        }

                        ControlArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.setSleepTimeout(modelData.sec)
                        }
                    }
                }
            }

            // Caffeine / Keep Awake Card
            Rectangle {
                id: caffeineCard
                width: parent.width
                height: 64
                radius: Theme.radius
                color: page.caffeineActive ? Theme.tint(Theme.accent, 0.08) : Theme.tint("#ffffff", 0.03)
                border.width: 1
                border.color: page.caffeineActive ? Theme.borderAccent : Theme.border

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
                        width: 36
                        height: 36
                        radius: Theme.radiusSm
                        color: page.caffeineActive ? Theme.tint(Theme.accent, 0.2) : Theme.tint("#ffffff", 0.06)
                        border.width: 1
                        border.color: page.caffeineActive ? Theme.borderAccent : Theme.border
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: page.caffeineActive ? "󰅶" : "󰛊"
                            font.family: Theme.iconFont
                            font.pixelSize: 18
                            color: page.caffeineActive ? Theme.accent : Theme.textDim
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: "Keep Screen Awake (Caffeine)"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }

                        Text {
                            text: page.caffeineActive ? "Screen lock and idle sleep inhibited" : "Screen follows normal timeout and sleep rules"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSecondary
                        }
                    }
                }

                // Switch Toggle
                Rectangle {
                    id: caffeineSwitch
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 24
                    radius: 12
                    color: page.caffeineActive ? Theme.accent : Theme.tint("#ffffff", 0.1)
                    border.width: 1
                    border.color: page.caffeineActive ? Theme.borderAccent : Theme.borderStrong

                    Behavior on color {
                        ColorAnimation { duration: Theme.animFast }
                    }

                    Rectangle {
                        id: switchThumb
                        width: 18
                        height: 18
                        radius: 9
                        color: page.caffeineActive ? "#ffffff" : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                        x: page.caffeineActive ? parent.width - width - 3 : 3

                        Behavior on x {
                            NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic }
                        }
                    }
                }

                ControlArea {
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

            // Quick Modes
            Text {
                text: "Modes & performance"
                color: Theme.text
                topPadding: 4
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
                font.letterSpacing: 0
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
                    height: 48
                    radius: Theme.radius
                    color: Theme.tint("#ffffff", 0.03)
                    border.width: 1
                    border.color: Theme.border

                    Item {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: modePill.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        height: 36

                        Text {
                            id: modeIcon
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: modeRoot.modelData.icon
                            color: Theme.accent
                            font.family: Theme.iconFont
                            font.pixelSize: 17
                        }

                        Column {
                            anchors.left: modeIcon.right
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: modeRoot.modelData.label
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: modeRoot.modelData.desc
                                color: Theme.textFaint
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSecondary
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Rectangle {
                        id: modePill
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 68
                        height: 26
                        radius: Theme.radiusSm
                        color: Theme.tint(Theme.accent, 0.12)
                        border.width: 1
                        border.color: Theme.tint(Theme.accent, 0.3)

                        Text {
                            anchors.centerIn: parent
                            text: modeRoot.modelData.action
                            color: Theme.accent
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fontSecondary
                            font.bold: true
                            font.letterSpacing: 0
                        }
                    }

                    ControlArea {
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
        }

        ScrollBar.vertical: SettingsScrollBar {}
    }
}
