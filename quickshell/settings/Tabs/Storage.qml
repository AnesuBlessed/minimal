import "../"
import QtQuick
import QtQuick.Controls
import Quickshell.Io

Item {
    id: page

    property var drives: []
    property var deviceOwners: ({})
    property var filesystems: []
    property var cleanupInfo: ({
        "yay": 0,
        "pacman": 0,
        "journal": 0,
        "trash": 0,
        "flatpak": 0,
        "cliphist": 0,
        "thumbs": 0
    })
    property var sdaUsageData: null
    property real marginLeft: 0
    property real marginRight: 12
    property real marginTop: 0
    property real marginBottom: 0
    property string pendingAction: ""
    property string pendingTitle: ""
    property string pendingMessage: ""
    property string lastAction: ""
    readonly property var sizeUnits: ({
        "B": 1,
        "K": 1024,
        "KB": 1024,
        "KIB": 1024,
        "M": 1.04858e+06,
        "MB": 1.04858e+06,
        "MIB": 1.04858e+06,
        "G": 1.07374e+09,
        "GB": 1.07374e+09,
        "GIB": 1.07374e+09,
        "T": 1.09951e+12,
        "TB": 1.09951e+12,
        "TIB": 1.09951e+12
    })

    function formatBytes(b) {
        if (!isFinite(b) || b < 0)
            return "0 B";

        var units = ["B", "KB", "MB", "GB", "TB"];
        var i = 0;
        var v = b;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            ++i;
        }
        return (i ? v.toFixed(1) : Math.round(v)) + " " + units[i];
    }

    function formatCount(n) {
        var v = Math.round(n) || 0;
        return v + (v === 1 ? " ITEM" : " ITEMS");
    }

    function parseSize(v) {
        if (!v)
            return 0;

        var m = String(v).trim().match(/^([0-9.]+)\s*([A-Za-z]*)$/);
        if (!m)
            return 0;

        var n = parseFloat(m[1]);
        if (isNaN(n))
            return 0;

        return n * (m[2] ? (sizeUnits[m[2]] || 1) : 1);
    }

    function usageColor(p) {
        return p >= 90 ? Theme.danger : p >= 75 ? Theme.accent2 : Theme.accent;
    }

    function usageWidth(p) {
        return Math.min(1, Math.max(0, p / 100));
    }

    function ignoredMount(m) {
        return ["/proc", "/sys", "/run", "/dev"].some(function(x) {
            return m.indexOf(x) === 0;
        });
    }

    function ignoredFilesystem(f) {
        return ["tmpfs", "devtmpfs", "overlay"].some(function(x) {
            return f.indexOf(x) === 0;
        });
    }

    function parseDfLine(line) {
        var f = line.trim().split(/\s+/);
        if (f.length < 6)
            return null;

        var d = {
            "filesystem": f[0],
            "total": parseInt(f[1]),
            "used": parseInt(f[2]),
            "available": parseInt(f[3]),
            "percent": parseInt(f[4]),
            "mount": f.slice(5).join(" ")
        };
        if ([d.total, d.used, d.available, d.percent].some(isNaN))
            return null;

        if (ignoredMount(d.mount) || ignoredFilesystem(d.filesystem))
            return null;

        return d;
    }

    function parseDriveData(data) {
        var disks = [];
        try {
            var obj = JSON.parse(data);
            if (!obj.blockdevices)
                return disks;

            var owners = {};
            function collect(node, disk) {
                var path = node.path || ("/dev/" + node.name);
                if (!owners[path]) owners[path] = [];
                if (owners[path].indexOf(disk) < 0) owners[path].push(disk);
                for (var child of (node.children || [])) collect(child, disk);
            }
            for (var i = 0; i < obj.blockdevices.length; ++i) {
                var d = obj.blockdevices[i];
                collect(d, d.name);
                if (d.type === "disk" && d.name.indexOf("loop") !== 0 && d.name.indexOf("zram") !== 0)
                    disks.push({
                    "name": d.name || "",
                    "model": d.model || "",
                    "size": parseInt(d.size) || 0,
                    "type": d.type || "",
                    "tran": d.tran || ""
                });

            }
        } catch (e) {
            console.warn("[Storage] lsblk JSON error:", e);
        }
        page.deviceOwners = owners || {};
        return disks;
    }

    function findDriveUsage(driveName) {
        if (!driveName)
            return null;

        var used = 0;
        var found = false;
        var seenDevices = {};
        for (var i = 0; i < filesystems.length; ++i) {
            var fs = filesystems[i];
            var owners = page.deviceOwners[(fs.filesystem || "").split("[")[0]] || [];
            if (owners.length === 1 && owners[0] === driveName) {
                if (!seenDevices[fs.filesystem]) {
                    seenDevices[fs.filesystem] = true;
                    used += fs.used;
                    found = true;
                }
            }
        }
        return found ? {
            "used": used
        } : null;
    }

    function refreshAll() {
        if (!pDrives.running)
            pDrives.running = true;

        if (!pStorage.running)
            pStorage.running = true;

        if (!pCleanup.running)
            pCleanup.running = true;

    }

    function confirmAction(title, message, command) {
        pendingTitle = title;
        pendingMessage = message;
        pendingAction = command;
        confirmPopup.visible = true;
    }

    function runCommand(command) {
        if (commandProcess.running) {
            console.warn("[Storage] Another command is still running.");
            return ;
        }
        lastAction = command;
        commandProcess.command = ["sh", "-c", command];
        commandProcess.running = true;
    }

    Component.onCompleted: page.refreshAll()

    Process {
        id: pDrives

        command: ["sh", "-c", "lsblk -J -b -o NAME,MODEL,SIZE,TYPE,TRAN,PATH 2>/dev/null"]

        stdout: StdioCollector {
            onStreamFinished: {
                page.drives = page.parseDriveData(text);
            }
        }

        stderr: StdioCollector {
        }

    }

    Process {
        id: pStorage

        command: ["sh", "-c", "df -P -B1 2>/dev/null"]

        stdout: StdioCollector {
            onStreamFinished: {
                var fs = [];
                var seenFsys = {};
                var lines = text.trim().split("\n");
                for (var i = 1; i < lines.length; ++i) {
                    var item = page.parseDfLine(lines[i]);
                    if (item) {
                        if (!seenFsys[item.filesystem]) {
                            seenFsys[item.filesystem] = item;
                            fs.push(item);
                        } else if (item.mount === "/" || item.mount === "/home") {
                            for (var k = 0; k < fs.length; ++k) {
                                if (fs[k].filesystem === item.filesystem) {
                                    fs[k] = item;
                                    break;
                                }
                            }
                        }
                    }
                }
                page.filesystems = fs;
            }
        }

        stderr: StdioCollector {
        }

    }

    Process {
        id: pCleanup

        command: ["sh", "-c", "p() { printf '%s %s\\n' \"$1\" \"${2:-0}\"; }; " + "p PACMAN \"$(du -sb /var/cache/pacman/pkg 2>/dev/null | awk '{print $1}')\"; " + "p JOURNAL \"$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+ ?[BKMGT]' | tail -1 | tr -d ' ')\"; " + "p TRASH \"$(du -sb \"$HOME/.local/share/Trash\" 2>/dev/null | awk '{print $1}')\"; " + "p FLATPAK \"$(flatpak uninstall --unused --assumeno 2>/dev/null | grep -oE '[0-9.]+ ?(kB|MB|GB|TB)' | tail -1 | tr -d ' ')\"; " + "p CLIPHIST \"$(cliphist list 2>/dev/null | wc -l)\"; " + "p THUMBS \"$(du -sb \"$HOME/.cache/thumbnails\" \"$HOME/.cache/quickshell/thumbs\" 2>/dev/null | awk '{s+=$1} END {print s}')\""]

        stdout: StdioCollector {
            onStreamFinished: {
                var info = {
                    "yay": 0,
                    "pacman": 0,
                    "journal": 0,
                    "trash": 0,
                    "flatpak": 0,
                    "cliphist": 0,
                    "thumbs": 0
                };
                var lines = text.trim().split("\n");
                for (var i = 0; i < lines.length; ++i) {
                    var p = lines[i].trim().split(/\s+/);
                    var k = p[0] ? p[0].toLowerCase() : "";
                    if (p.length > 1 && info[k] !== undefined)
                        info[k] = page.parseSize(p.slice(1).join(" "));

                }
                page.cleanupInfo = info;
            }
        }

        stderr: StdioCollector {
        }

    }

    Process {
        id: commandProcess

        onRunningChanged: {
            if (!running)
                refreshTimer.restart();

        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    console.log("[Storage] " + text.trim());

            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    console.warn("[Storage] " + text.trim());

            }
        }

    }

    Timer {
        id: refreshTimer

        interval: 500
        repeat: false
        onTriggered: page.refreshAll()
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: page.refreshAll()
    }

    Rectangle {
        id: confirmPopup

        visible: false
        anchors.centerIn: parent
        z: 100
        width: Math.min(parent.width - 30, 420)
        height: 190
        radius: Theme.radius
        color: Theme.bg
        border.width: 1
        border.color: Theme.accent

        Column {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            Text {
                text: page.pendingTitle
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 17
                font.bold: true
            }

            Text {
                width: parent.width
                text: page.pendingMessage
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Item {
                width: 1
                height: 1
            }

            Row {
                width: parent.width
                spacing: 10

                ToolButton {
                    width: (parent.width - 10) / 2
                    label: "CANCEL"
                    onClicked: confirmPopup.visible = false
                }

                ToolButton {
                    width: (parent.width - 10) / 2
                    label: "CONFIRM"
                    accent: true
                    onClicked: {
                        confirmPopup.visible = false;
                        page.runCommand(page.pendingAction);
                    }
                }

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

        Item {
            width: parent.width
            height: Math.max(0, parent.height - y)

            Flickable {
                id: flick

                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: list.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: list

                    width: Math.max(0, flick.width - 10)
                    spacing: 10

                    Text {
                        text: "Drives"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                        font.letterSpacing: 0
                    }

                    Repeater {
                        model: page.drives

                        delegate: Item {
                            required property var modelData
                            property var usageData: page.findDriveUsage(modelData.name)
                            property bool hasUsage: usageData !== null && modelData.size > 0
                            property real usedPct: hasUsage ? (usageData.used / modelData.size * 100) : 0

                            width: list.width
                            height: 64

                            Column {
                                anchors.fill: parent
                                spacing: 9

                                Row {
                                    width: parent.width
                                    height: 17

                                    Text {
                                        width: parent.width - 70
                                        text: modelData.model || modelData.name || "SSD/HDD"
                                        color: Theme.text
                                        elide: Text.ElideRight
                                        verticalAlignment: Text.AlignVCenter
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                    }

                                    Text {
                                        width: 70
                                        text: hasUsage ? Math.round(usedPct) + "%" : "--%"
                                        color: hasUsage ? page.usageColor(usedPct) : Theme.textDim
                                        horizontalAlignment: Text.AlignRight
                                        verticalAlignment: Text.AlignVCenter
                                        font.family: Theme.monoFont
                                        font.pixelSize: 12
                                        font.bold: true
                                    }

                                }

                                Rectangle {
                                    width: parent.width
                                    height: 4
                                    radius: 2
                                    color: Theme.alpha(Theme.textDim, 0.15)

                                    Rectangle {
                                        width: hasUsage ? parent.width * page.usageWidth(usedPct) : 0
                                        height: parent.height
                                        radius: 2
                                        color: hasUsage ? page.usageColor(usedPct) : Theme.accent

                                        Behavior on width {
                                            NumberAnimation {
                                                duration: Theme.animMed
                                            }

                                        }

                                    }

                                }

                                Row {
                                    width: parent.width
                                    height: 13
                                    spacing: 14

                                    Text {
                                        text: hasUsage ? page.formatBytes(usageData.used) + " mounted data" : "Usage unavailable"
                                        color: Theme.textDim
                                        font.family: Theme.monoFont
                                        font.pixelSize: Theme.fontSecondary
                                    }

                                    Text {
                                        text: ""
                                        color: Theme.textDim
                                        font.family: Theme.monoFont
                                        font.pixelSize: Theme.fontSecondary
                                    }

                                    Text {
                                        text: page.formatBytes(modelData.size) + " capacity"
                                        color: Theme.textDim
                                        font.family: Theme.monoFont
                                        font.pixelSize: Theme.fontSecondary
                                    }

                                }

                            }

                        }

                    }

                    Text {
                        text: "Filesystem"
                        color: Theme.text
                        topPadding: 4
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                        font.letterSpacing: 0
                    }

                    Repeater {
                        model: page.filesystems

                        delegate: Item {
                            required property var modelData

                            width: list.width
                            height: 64

                            Column {
                                anchors.fill: parent
                                spacing: 9

                                Row {
                                    width: parent.width
                                    height: 17

                                    Text {
                                        width: parent.width - 55
                                        text: modelData.mount
                                        color: Theme.text
                                        elide: Text.ElideRight
                                        verticalAlignment: Text.AlignVCenter
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 13
                                        font.bold: true
                                    }

                                    Text {
                                        width: 55
                                        text: modelData.percent + "%"
                                        color: page.usageColor(modelData.percent)
                                        horizontalAlignment: Text.AlignRight
                                        verticalAlignment: Text.AlignVCenter
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                        font.bold: true
                                    }

                                }

                                Rectangle {
                                    width: parent.width
                                    height: 4
                                    radius: 2
                                    color: Theme.alpha(Theme.textDim, 0.15)

                                    Rectangle {
                                        width: parent.width * page.usageWidth(modelData.percent)
                                        height: parent.height
                                        radius: 2
                                        color: page.usageColor(modelData.percent)

                                        Behavior on width {
                                            NumberAnimation {
                                                duration: Theme.animMed
                                            }

                                        }

                                    }

                                }

                                Row {
                                    width: parent.width
                                    height: 13
                                    spacing: 14

                                    Text {
                                        text: page.formatBytes(modelData.used) + " USED"
                                        color: Theme.textDim
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSecondary
                                    }

                                    Text {
                                        text: page.formatBytes(modelData.available) + " FREE"
                                        color: Theme.textDim
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSecondary
                                    }

                                    Text {
                                        text: page.formatBytes(modelData.total) + " TOTAL"
                                        color: Theme.textDim
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSecondary
                                    }

                                }

                            }

                        }

                    }

                    Text {
                        text: "System rescue & quick tools"
                        color: Theme.text
                        topPadding: 6
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                        font.letterSpacing: 0
                    }

                    Repeater {
                        model: [{
                            "icon": "󰅙",
                            "label": "Kill Frozen Window",
                            "desc": "Click any stuck or unresponsive window to immediately terminate it",
                            "action": "Arm",
                            "command": "hyprctl kill"
                        }, {
                            "icon": "⏏",
                            "label": "Safely Eject USB Drives",
                            "desc": "Unmount external flash drives or removable media safely",
                            "action": "EJECT",
                            "command": "bash -c 'if [ -x \"$MINIMAL_ROOT/scripts/usb-menu.sh\" ]; then \"$MINIMAL_ROOT/scripts/usb-menu.sh\"; elif command -v udiskie-umount >/dev/null; then udiskie-umount -a && notify-send \"USB\" \"Removable drives unmounted\"; else notify-send \"USB\" \"No eject tool available\"; fi'"
                        }, {
                            "icon": "󰓃",
                            "label": "Restart Audio Stack",
                            "desc": "Restart PipeWire & WirePlumber to fix crackling or desynced sound",
                            "action": "RESTART",
                            "command": "systemctl --user restart pipewire pipewire-pulse wireplumber"
                        }]

                        delegate: QuickToolButton {
                            required property var modelData

                            width: list.width
                            icon: modelData.icon
                            label: modelData.label
                            desc: modelData.desc
                            actionText: modelData.action
                            onClicked: page.runCommand(modelData.command)
                        }
                    }

                    Text {
                        text: "Cleanup"
                        color: Theme.text
                        topPadding: 6
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                        font.letterSpacing: 0
                    }

                    Repeater {
                        model: [{
                            "key": "trash",
                            "label": "TRASH",
                            "action": "EMPTY",
                            "title": "EMPTY TRASH?",
                            "message": "Permanently deletes the contents of your trash.",
                            "command": "python3 \"$MINIMAL_ROOT/scripts/maintenance.py\" trash"
                        }, {
                            "key": "cliphist",
                            "label": "CLIPHIST",
                            "action": "WIPE",
                            "title": "WIPE CLIPBOARD HISTORY?",
                            "message": "Clears the clipboard history.",
                            "command": "python3 \"$MINIMAL_ROOT/scripts/maintenance.py\" clipboard"
                        }, {
                            "key": "thumbs",
                            "label": "THUMBNAILS & CACHE",
                            "action": "CLEAR",
                            "title": "CLEAR THUMBNAIL CACHES?",
                            "message": "Clears system and Quickshell image and thumbnail caches.",
                            "command": "python3 \"$MINIMAL_ROOT/scripts/maintenance.py\" thumbnails"
                        }, {
                            "key": "journal",
                            "label": "JOURNAL LOGS",
                            "action": "VACUUM",
                            "title": "VACUUM JOURNAL LOGS?",
                            "message": "Trims system and user systemd journals down to 10MB.",
                            "command": "journalctl --user --vacuum-size=10M && notify-send 'Maintenance' 'User journals trimmed to 10MB'"
                        }, {
                            "key": "pacman",
                            "label": "PACMAN CACHE",
                            "action": "CLEAN",
                            "title": "CLEAN PACMAN CACHE?",
                            "message": "Removes outdated package tarballs from pacman cache keeping the latest version.",
                            "command": "pkexec paccache -rk1 && notify-send 'Maintenance' 'Pacman cache cleaned'"
                        }, {
                            "key": "flatpak",
                            "label": "FLATPAK UNUSED",
                            "action": "CLEAN",
                            "title": "REMOVE UNUSED FLATPAKS?",
                            "message": "Removes unused Flatpak runtimes and packages.",
                            "command": "flatpak uninstall --unused --assumeyes && notify-send 'Maintenance' 'Unused Flatpaks removed'"
                        }]

                        delegate: CleanupButton {
                            required property var modelData

                            width: list.width
                            label: modelData.label
                            value: modelData.key === "cliphist" ? page.formatCount(page.cleanupInfo.cliphist) : page.formatBytes(page.cleanupInfo[modelData.key])
                            actionText: modelData.action
                            onClicked: page.confirmAction(modelData.title, modelData.message, modelData.command)
                        }

                    }

                }

                ScrollBar.vertical: SettingsScrollBar {}

            }

        }

    }

    component ToolButton: Rectangle {
        property string label: ""
        property bool accent: false

        signal clicked()

        height: 38
        radius: Theme.radius
        color: "#00000000"
        border.width: 1
        border.color: Theme.border

        Text {
            anchors.centerIn: parent
            text: parent.label
            color: parent.accent ? Theme.accent : Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSecondary
            font.bold: true
            font.letterSpacing: 0
        }

        ControlArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                parent.color = Theme.alpha(Theme.accent, 0.08);
                parent.border.color = Theme.accent;
            }
            onExited: {
                parent.color = "#00000000";
                parent.border.color = Theme.border;
            }
            onClicked: parent.clicked()
        }

    }

    component CleanupButton: Rectangle {
        id: cleanupRoot

        required property string label
        required property string value
        required property string actionText

        signal clicked()

        width: parent.width
        height: 42
        radius: Theme.radius
        color: "#00000000"
        border.width: 1
        border.color: Theme.border

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: cleanupRoot.label
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.bold: true
            font.letterSpacing: 0
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                text: cleanupRoot.value
                color: Theme.textDim
                font.family: Theme.monoFont
                font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: cleanupRoot.actionText
                color: Theme.textDim
                font.family: Theme.monoFont
                font.pixelSize: 12
                font.bold: true
                font.letterSpacing: 0
                anchors.verticalCenter: parent.verticalCenter
            }

        }

        ControlArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                parent.color = Theme.alpha(Theme.accent, 0.08);
                parent.border.color = Theme.accent;
            }
            onExited: {
                parent.color = "#00000000";
                parent.border.color = Theme.border;
            }
            onClicked: cleanupRoot.clicked()
        }

    }

    component QuickToolButton: Rectangle {
        id: toolRoot

        required property string icon
        required property string label
        required property string desc
        required property string actionText

        signal clicked()

        width: parent.width
        height: 52
        radius: Theme.radius
        color: Theme.tint("#ffffff", 0.03)
        border.width: 1
        border.color: Theme.border

        Text {
            id: toolIcon
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: toolRoot.icon
            color: Theme.accent
            font.family: Theme.iconFont
            font.pixelSize: 18
        }

        Column {
            anchors.left: toolIcon.right
            anchors.leftMargin: 12
            anchors.right: actionPill.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: toolRoot.label
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: toolRoot.desc
                color: Theme.textFaint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSecondary
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: actionPill

            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: actionTextLabel.implicitWidth + 20
            height: 28
            radius: Theme.radiusSm
            color: Theme.tint(Theme.accent, 0.12)
            border.width: 1
            border.color: Theme.tint(Theme.accent, 0.3)

            Text {
                id: actionTextLabel

                anchors.centerIn: parent
                text: toolRoot.actionText
                color: Theme.accent
                font.family: Theme.monoFont
                font.pixelSize: Theme.fontSecondary
                font.weight: Font.Bold
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
            onClicked: toolRoot.clicked()
        }
    }

}
