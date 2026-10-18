import "../"
import QtQuick
import QtQuick.Controls
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io

Item {
    id: page

    property var monitors: []
    property string actionError: ""
    property var savedState: ({
    })
    property real marginLeft: 0
    property real marginRight: 12
    property real marginTop: 0
    property real marginBottom: 0
    readonly property var activeMonitors: monitors.filter((m) => {
        return !m.disabled;
    })
    property var pendingScaleMonitor: null
    property real pendingScaleValue: 1
    property real pendingRate: -1
    property string pendingRateMonitor: ""
    property string pendingRes: ""
    property string pendingResMonitor: ""

    readonly property var bboxCenter: {
        if (activeMonitors.length === 0)
            return { "x": 0, "y": 0 };

        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (let i = 0; i < activeMonitors.length; i++) {
            const m = activeMonitors[i];
            const s = m.scale > 0 ? m.scale : 1;
            const x1 = Number(m.x || 0);
            const y1 = Number(m.y || 0);
            const x2 = x1 + m.width / s;
            const y2 = y1 + m.height / s;
            minX = Math.min(minX, x1, x2);
            minY = Math.min(minY, y1, y2);
            maxX = Math.max(maxX, x1, x2);
            maxY = Math.max(maxY, y1, y2);
        }
        return {
            "x": (minX + maxX) / 2,
            "y": (minY + maxY) / 2
        };
    }

    function monitorMode(mon) {
        const rate = Number(mon.refreshRate);
        const safeRate = isNaN(rate) ? 0 : rate;
        return mon.width + "x" + mon.height + "@" + safeRate.toFixed(2);
    }

    function applyMonitorSettings(name, mode, pos, scale, disabled) {
        if (pShell.running) return;
        page.actionError = "";
        var rootDir = Quickshell.env("MINIMAL_ROOT") || ((Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/minimal");
        pShell.command = ["python3", rootDir + "/scripts/monitors.py", "--configure",
            JSON.stringify({name: name, mode: mode || "preferred", position: pos || "auto",
                            scale: scale || 1, disabled: Boolean(disabled)})];
        pShell.running = true;
    }

    function applyPreset(preset) {
        pShell.command = ["sh", "-c", "python3 \"$MINIMAL_ROOT/scripts/monitors.py\" --preset '" + preset + "'"];
        pShell.running = true;
    }

    function resetToConfig() {
        pReset.command = ["sh", "-c", "rm -f \"$MINIMAL_STATE/monitors.json\" \"$MINIMAL_STATE/monitors.lua\"; hyprctl reload; python3 \"$MINIMAL_ROOT/scripts/monitors.py\" --preset extend-right 2>/dev/null || true"];
        pReset.running = true;
    }

    function setPosition(mon, x, y) {
        if (!mon || !mon.name)
            return ;

        const position = Math.round(Number(x)) + "x" + Math.round(Number(y));
        const mode = monitorMode(mon);
        const scale = mon.scale !== undefined ? mon.scale : 1;
        applyMonitorSettings(mon.name, mode, position, scale, false);
    }

    function gluePosition(movedMon, x, y, w, h) {
        if (activeMonitors.length <= 1)
            return { "x": Math.round(x), "y": Math.round(y) };

        let bestDist = Infinity;
        let best = { "x": Math.round(x), "y": Math.round(y) };

        for (let i = 0; i < activeMonitors.length; i++) {
            const other = activeMonitors[i];
            if (other.name === movedMon.name)
                continue;

            const s = other.scale > 0 ? other.scale : 1;
            const ox = Number(other.x || 0);
            const oy = Number(other.y || 0);
            const ow = other.width / s;
            const oh = other.height / s;

            const candidates = [
                { "x": ox + ow, "y": y, "dist": Math.abs(ox + ow - x) }, 
                { "x": ox - w,  "y": y, "dist": Math.abs(ox - w - x) },  
                { "x": x, "y": oy - h,  "dist": Math.abs(oy - h - y) },   
                { "x": x, "y": oy + oh, "dist": Math.abs(oy + oh - y) }  
            ];

            for (let c = 0; c < candidates.length; c++) {
                const cand = candidates[c];
                if (cand.dist < bestDist) {
                    bestDist = cand.dist;
                    best = { "x": Math.round(cand.x), "y": Math.round(cand.y) };
                }
            }
        }

        return best;
    }

    function graphScale(graphWidth, graphHeight) {
        if (activeMonitors.length === 0)
            return 0.15;

        const cx = bboxCenter.x;
        const cy = bboxCenter.y;
        let maxHalfW = 150, maxHalfH = 100;

        for (let i = 0; i < activeMonitors.length; i++) {
            const m = activeMonitors[i];
            const s = m.scale > 0 ? m.scale : 1;
            const x1 = Number(m.x || 0) - cx;
            const y1 = Number(m.y || 0) - cy;
            const x2 = x1 + m.width / s;
            const y2 = y1 + m.height / s;
            maxHalfW = Math.max(maxHalfW, Math.abs(x1), Math.abs(x2));
            maxHalfH = Math.max(maxHalfH, Math.abs(y1), Math.abs(y2));
        }

        const margin = 24;
        const availW = Math.max(50, graphWidth / 2 - margin);
        const availH = Math.max(50, graphHeight / 2 - margin);
        return Math.max(0.025, Math.min(availW / maxHalfW, availH / maxHalfH, 0.25));
    }

    function isMain(mon) {
        return !mon.disabled && page.activeMonitors.length > 0 && mon.x === 0 && mon.y === 0;
    }

    function setMainMonitor(main) {
        if (!main || !main.name || main.disabled)
            return ;

        pShell.command = ["sh", "-c", "hyprctl dispatch focusmonitor '" + main.name + "'"];
        pShell.running = true;
    }

    function setMonitorEnabled(mon, enabled) {
        if (!mon || !mon.name)
            return ;

        if (enabled) {
            applyMonitorSettings(mon.name, monitorMode(mon), (mon.x || 0) + "x" + (mon.y || 0), mon.scale || 1, false);
        } else {
            if (page.activeMonitors.length <= 1)
                return ;

            applyMonitorSettings(mon.name, monitorMode(mon), (mon.x || 0) + "x" + (mon.y || 0), mon.scale || 1, true);
        }
    }

    function refresh() {
        pList.running = true;
    }

    function scaleOptions(mon) {
        if (!mon || !mon.width || !mon.height)
            return [];

        const options = [];
        const width = mon.width;
        const height = mon.height;
        for (let i = 84; i <= 1560; i++) {
            const scale = i / 120;
            if (scale < 0.7 || scale > 1.3)
                continue;

            const logicalWidth = width / scale;
            const logicalHeight = height / scale;
            if (Math.abs(logicalWidth - Math.round(logicalWidth)) < 0.01 && Math.abs(logicalHeight - Math.round(logicalHeight)) < 0.01) {
                options.push(scale);
            }
        }
        return options;
    }

    function validScale(mon, requested) {
        const options = page.scaleOptions(mon);
        if (options.length === 0)
            return 1.0;

        let best = options[0];
        let bestDistance = Math.abs(options[0] - requested);
        for (let i = 1; i < options.length; i++) {
            const d = Math.abs(options[i] - requested);
            if (d < bestDistance) {
                best = options[i];
                bestDistance = d;
            }
        }
        return best;
    }

    function hasScaleOptions(mon) {
        return page.scaleOptions(mon).length > 1;
    }

    function setScale(mon, scale, isRetry = false) {
        if (!mon || !mon.name)
            return ;

        const requested = Number(scale);
        const applied = isRetry ? requested : validScale(mon, requested);
        const idx = page.monitors.findIndex((m) => {
            return m.name === mon.name;
        });
        if (idx !== -1) {
            const updated = page.monitors.slice();
            updated[idx] = Object.assign({
            }, updated[idx], {
                "scale": applied
            });
            page.monitors = updated;
        }
        const mode = monitorMode(mon);
        const position = (mon.x !== undefined ? mon.x : 0) + "x" + (mon.y !== undefined ? mon.y : 0);
        applyMonitorSettings(mon.name, mode, position, applied, false);
    }

    function resolutionList(mon) {
        if (!mon || !mon.availableModes)
            return [];

        const seen = {
        };
        const items = [];
        for (let i = 0; i < mon.availableModes.length; i++) {
            const match = String(mon.availableModes[i]).match(/^(\d+)x(\d+)@/);
            if (!match)
                continue;

            const key = match[1] + "x" + match[2];
            if (seen[key])
                continue;

            seen[key] = true;
            items.push({
                "key": key,
                "width": parseInt(match[1]),
                "height": parseInt(match[2])
            });
        }
        items.sort((a, b) => {
            return (b.width * b.height - a.width * a.height) || (b.width - a.width);
        });
        return items.slice(0, 6).map((item) => {
            return item.key;
        });
    }

    function bestMode(mon, resolution) {
        if (!mon || !mon.availableModes)
            return null;

        const prefix = resolution + "@";
        let bestRate = null;
        let bestDistance = Infinity;
        for (let i = 0; i < mon.availableModes.length; i++) {
            const mode = String(mon.availableModes[i]);
            if (mode.indexOf(prefix) !== 0)
                continue;

            const rate = parseFloat(mode.substring(prefix.length));
            if (isNaN(rate))
                continue;

            const distance = Math.abs(rate - mon.refreshRate);
            if (distance < bestDistance || (distance === bestDistance && rate > bestRate)) {
                bestRate = rate;
                bestDistance = distance;
            }
        }
        return bestRate === null ? null : prefix + bestRate.toFixed(2);
    }

    function setResolution(mon, mode) {
        if (!mon || !mon.name || !mode)
            return ;

        const match = mode.match(/^(\d+)x(\d+)/);
        if (match) {
            page.pendingRes = match[1] + "x" + match[2];
            page.pendingResMonitor = mon.name;
            for (let i = 0; i < page.monitors.length; i++) {
                if (page.monitors[i].name === mon.name) {
                    let copy = page.monitors.slice();
                    copy[i] = Object.assign({}, copy[i], { width: parseInt(match[1]), height: parseInt(match[2]) });
                    page.monitors = copy;
                    break;
                }
            }
        }

        const scale = mon.scale !== undefined ? mon.scale : 1;
        const position = (mon.x !== undefined ? mon.x : 0) + "x" + (mon.y !== undefined ? mon.y : 0);
        applyMonitorSettings(mon.name, mode, position, scale, false);
    }

    function refreshRates(mon) {
        if (!mon || !mon.availableModes)
            return [];

        const prefix = mon.width + "x" + mon.height + "@";
        const seen = {
        };
        const rates = [];
        for (let i = 0; i < mon.availableModes.length; i++) {
            const mode = String(mon.availableModes[i]);
            if (mode.indexOf(prefix) !== 0)
                continue;

            const match = mode.match(/@([\d.]+)/);
            if (!match)
                continue;

            const rate = parseFloat(match[1]);
            if (isNaN(rate))
                continue;

            const key = rate.toFixed(2);
            if (seen[key])
                continue;

            seen[key] = true;
            rates.push(rate);
        }
        rates.sort((a, b) => {
            return b - a;
        });
        return rates;
    }

    function setRefreshRate(mon, rate) {
        if (!mon || !mon.name || rate === undefined)
            return ;

        page.pendingRate = Number(rate);
        page.pendingRateMonitor = mon.name;
        for (let i = 0; i < page.monitors.length; i++) {
            if (page.monitors[i].name === mon.name) {
                let copy = page.monitors.slice();
                copy[i] = Object.assign({}, copy[i], { refreshRate: Number(rate) });
                page.monitors = copy;
                break;
            }
        }

        const mode = mon.width + "x" + mon.height + "@" + Number(rate).toFixed(2);
        const scale = mon.scale !== undefined ? mon.scale : 1;
        const position = (mon.x !== undefined ? mon.x : 0) + "x" + (mon.y !== undefined ? mon.y : 0);
        applyMonitorSettings(mon.name, mode, position, scale, false);
    }

    Component.onCompleted: page.refresh()

    Process {
        id: pReset
        onExited: (exitCode) => {
            if (exitCode !== 0 && !page.actionError) page.actionError = "Could not apply display settings.";
            refreshTimer.restart();
        }
    }

    Process {
        id: pShell
        stderr: StdioCollector {
            onStreamFinished: { if (text.trim()) page.actionError = text.trim(); }
        }
        onExited: (exitCode) => {
            if (exitCode !== 0 && !page.actionError) page.actionError = "Could not apply display settings.";
            refreshTimer.restart();
        }
    }

    Process {
        id: pList
        command: ["hyprctl", "monitors", "all", "-j"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.monitors = JSON.parse(text);
                } catch (error) {
                    page.monitors = [];
                }
                page.pendingRate = -1;
                page.pendingRateMonitor = "";
                page.pendingRes = "";
                page.pendingResMonitor = "";
            }
        }
    }

    Timer {
        id: scaleApplyTimer
        interval: 180
        repeat: false
        onTriggered: {
            if (page.pendingScaleMonitor)
                page.setScale(page.pendingScaleMonitor, page.pendingScaleValue);
        }
    }

    Timer {
        id: refreshTimer
        interval: 250
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
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            width: Math.max(0, flick.width - 10)
            spacing: 14
            Text {
                visible: page.actionError !== ""
                width: parent.width
                text: page.actionError
                color: Theme.danger
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBody
            }

            Row {
                width: parent.width
                spacing: 8
                visible: page.monitors.length > 1

                Repeater {
                    model: [
                        { "label": "EXTEND RIGHT", "preset": "extend-right" },
                        { "label": "EXTEND LEFT", "preset": "extend-left" },
                        { "label": "MIRROR", "preset": "mirror" },
                        { "label": "LAPTOP ONLY", "preset": "internal-only" },
                        { "label": "EXTERNAL ONLY", "preset": "external-only" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        width: (parent.width - 32) / 5
                        height: 30
                        radius: Theme.radiusSm
                        color: presetMouse.containsMouse ? Theme.alpha(Theme.accent, 0.15) : Theme.tint("#ffffff", 0.04)
                        border.width: 1
                        border.color: presetMouse.containsMouse ? Theme.borderAccent : Theme.border

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: presetMouse.containsMouse ? Theme.accent : Theme.textDim
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fontSecondary
                            font.bold: true
                            font.letterSpacing: 0
                        }

                        ControlArea {
                            id: presetMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.applyPreset(modelData.preset)
                        }
                    }
                }
            }

            Rectangle {
                id: monitorGraph

                property real scaleFactor: page.graphScale(width, height)
                property real centerX: page.bboxCenter.x
                property real centerY: page.bboxCenter.y

                width: parent.width
                height: page.activeMonitors.length > 1 ? 200 : 120
                radius: Theme.radius
                color: Theme.alpha(Theme.text, 0.025)
                border.width: 1
                border.color: Theme.border
                clip: true

                Repeater {
                    model: 5
                    delegate: Rectangle {
                        required property int index
                        x: (index + 1) * monitorGraph.width / 6
                        y: 0
                        width: 1
                        height: monitorGraph.height
                        color: Theme.alpha(Theme.text, 0.035)
                        z: 0
                    }
                }

                Rectangle {
                    x: 0
                    y: monitorGraph.height / 2
                    width: monitorGraph.width
                    height: 1
                    color: Theme.alpha(Theme.text, 0.08)
                    z: 0
                }

                Rectangle {
                    x: monitorGraph.width / 2 - 3
                    y: monitorGraph.height / 2 - 3
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.accent
                    z: 1
                }

                Repeater {
                    model: page.activeMonitors

                    delegate: Rectangle {
                        id: monitorTile

                        required property var modelData
                        required property int index

                        readonly property real tileScale: monitorGraph.scaleFactor
                        readonly property real tileW: modelData.width / (modelData.scale > 0 ? modelData.scale : 1)
                        readonly property real tileH: modelData.height / (modelData.scale > 0 ? modelData.scale : 1)

                        x: monitorGraph.width / 2 + (Number(modelData.x || 0) - monitorGraph.centerX) * tileScale
                        y: monitorGraph.height / 2 + (Number(modelData.y || 0) - monitorGraph.centerY) * tileScale
                        width: Math.max(52, tileW * tileScale)
                        height: Math.max(38, tileH * tileScale)
                        radius: 7
                        color: Theme.alpha(index === 0 ? Theme.accent : Theme.text, 0.13)
                        border.width: 2
                        border.color: page.isMain(modelData) ? Theme.accent : Theme.alpha(Theme.text, 0.42)
                        z: dragMouse.pressed ? 5 : 2

                        Column {
                            anchors.centerIn: parent
                            spacing: 3

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: monitorTile.modelData.name
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSecondary
                                font.bold: true
                            }

                            Rectangle {
                                width: 24
                                height: 2
                                radius: 1
                                color: Theme.alpha(Theme.text, 0.4)
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: monitorTile.modelData.width + " × " + monitorTile.modelData.height
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSecondary
                            }
                        }

                        MouseArea {
                            id: dragMouse

                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            preventStealing: true
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                            property real pressGraphX: 0
                            property real pressGraphY: 0
                            property real startWorldX: 0
                            property real startWorldY: 0
                            property bool moved: false

                            function applyGlue(mouseX, mouseY) {
                                const factor = monitorGraph.scaleFactor;
                                const p = dragMouse.mapToItem(monitorGraph, mouseX, mouseY);
                                const dxWorld = (p.x - pressGraphX) / factor;
                                const dyWorld = (p.y - pressGraphY) / factor;
                                const wantX = startWorldX + dxWorld;
                                const wantY = startWorldY + dyWorld;

                                const glued = page.gluePosition(
                                    monitorTile.modelData,
                                    wantX, wantY,
                                    monitorTile.tileW, monitorTile.tileH
                                );

                                monitorTile.x = monitorGraph.width / 2 + (glued.x - monitorGraph.centerX) * factor;
                                monitorTile.y = monitorGraph.height / 2 + (glued.y - monitorGraph.centerY) * factor;

                                return glued;
                            }

                            onPressed: function(mouse) {
                                const p = dragMouse.mapToItem(monitorGraph, mouse.x, mouse.y);
                                pressGraphX = p.x;
                                pressGraphY = p.y;
                                startWorldX = Number(monitorTile.modelData.x || 0);
                                startWorldY = Number(monitorTile.modelData.y || 0);
                                moved = false;
                            }

                            onPositionChanged: function(mouse) {
                                if (!pressed)
                                    return ;
                                moved = true;
                                applyGlue(mouse.x, mouse.y);
                            }

                            onReleased: function(mouse) {
                                if (!moved)
                                    return ;
                                const glued = applyGlue(mouse.x, mouse.y);
                                page.setPosition(monitorTile.modelData, glued.x, glued.y);
                            }
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 8

                Repeater {
                    model: page.monitors

                    delegate: Rectangle {
                        id: card

                        required property var modelData
                        property bool off: modelData.disabled === true
                        property bool main: page.isMain(modelData)
                        readonly property bool scaleAvailable: page.hasScaleOptions(modelData)

                        width: parent.width
                        height: cardColumn.implicitHeight + 20
                        radius: Theme.radius
                        color: "#00000000"
                        border.width: 1
                        border.color: modelData.focused && !off ? "#454545" : Theme.border

                        Column {
                            id: cardColumn

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 10
                            spacing: 6

                            Item {
                                width: parent.width
                                height: 24

                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8

                                    Text {
                                        text: card.modelData.name
                                        color: card.off ? Theme.textDim : Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 14
                                        font.bold: true
                                    }

                                    Text {
                                        visible: !card.off
                                        text: card.modelData.width + "x" + card.modelData.height + " @ " + Math.round(card.modelData.refreshRate) + "Hz"
                                        color: Theme.textDim
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 12
                                    }
                                }

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    Rectangle {
                                        visible: !card.off && page.activeMonitors.length > 1
                                        width: 84
                                        height: 24
                                        radius: Theme.radius
                                        color: card.main ? Theme.alpha(Theme.accent, 0.1) : (mainMouse.containsMouse ? Theme.alpha(Theme.accent, 0.08) : "#00000000")
                                        border.width: 1
                                        border.color: card.main || mainMouse.containsMouse ? Theme.borderAccent : Theme.border

                                        Text {
                                            anchors.centerIn: parent
                                            text: card.main ? "MAIN" : "SET MAIN"
                                            color: card.main ? Theme.accent : Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSecondary
                                            font.bold: true
                                            font.letterSpacing: 0
                                        }

                                        ControlArea {
                                            id: mainMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: !card.main
                                            cursorShape: card.main ? Qt.ArrowCursor : Qt.PointingHandCursor
                                            onClicked: page.setMainMonitor(card.modelData)
                                        }
                                    }

                                    Rectangle {
                                        visible: card.off || page.activeMonitors.length > 1
                                        width: 72
                                        height: 24
                                        radius: Theme.radius
                                        color: toggleMouse.containsMouse ? Theme.alpha(Theme.accent, 0.08) : "#00000000"
                                        border.width: 1
                                        border.color: toggleMouse.containsMouse ? Theme.borderAccent : Theme.border

                                        Text {
                                            anchors.centerIn: parent
                                            text: card.off ? "ENABLE" : "DISABLE"
                                            color: Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSecondary
                                            font.bold: true
                                            font.letterSpacing: 0
                                        }

                                        ControlArea {
                                            id: toggleMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: page.setMonitorEnabled(card.modelData, card.off)
                                        }
                                    }
                                }
                            }

                            Row {
                                visible: !card.off
                                width: parent.width
                                spacing: 8

                                Text {
                                    width: 36
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Scale"
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSecondary
                                }

                                Controls.Slider {
                                    visible: card.scaleAvailable
                                    width: parent.width - 36 - 44 - 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    from: 0
                                    to: 1
                                    value: Math.max(0, Math.min(1, ((card.modelData.scale || 1) - 0.7) / 0.6))
                                    onMoved: {
                                        const newScale = 0.7 + value * 0.6;
                                        page.pendingScaleMonitor = card.modelData;
                                        page.pendingScaleValue = newScale;
                                        scaleApplyTimer.restart();
                                    }
                                }

                                Text {
                                    visible: !card.scaleAvailable
                                    width: parent.width - 36 - 44 - 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Only 1.00x available on this resolution"
                                    color: Theme.textFaint
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSecondary
                                    font.italic: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: 44
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: (card.modelData.scale || 1).toFixed(2) + "x"
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSecondary
                                }
                            }

                            Row {
                                visible: !card.off
                                width: parent.width
                                spacing: 8

                                Text {
                                    width: 36
                                    height: 28
                                    verticalAlignment: Text.AlignVCenter
                                    text: "RES"
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSecondary
                                }

                                Flow {
                                    width: parent.width - 36 - 8
                                    spacing: 6

                                    Repeater {
                                        model: card.off ? [] : page.resolutionList(card.modelData)

                                        delegate: Rectangle {
                                            id: resButton
                                            required property string modelData
                                            property bool isPending: page.pendingResMonitor === card.modelData.name && page.pendingRes !== ""
                                            property bool current: isPending ? (modelData === page.pendingRes) : (modelData === card.modelData.width + "x" + card.modelData.height)

                                            width: 92
                                            height: 28
                                            radius: Theme.radius
                                            color: current ? Theme.alpha(Theme.accent, 0.16) : (resMouse.containsMouse ? Theme.alpha(Theme.accent, 0.08) : "#00000000")
                                            border.width: current ? 1.5 : 1
                                            border.color: current ? Theme.accent : (resMouse.containsMouse ? Theme.borderAccent : Theme.border)

                                            Text {
                                                anchors.centerIn: parent
                                                text: resButton.modelData
                                                color: current ? Theme.accent : Theme.text
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSecondary
                                                font.bold: current
                                            }

                                            ControlArea {
                                                id: resMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    const mode = page.bestMode(card.modelData, resButton.modelData);
                                                    if (mode)
                                                        page.setResolution(card.modelData, mode);
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Row {
                                visible: !card.off
                                width: parent.width
                                spacing: 8

                                Text {
                                    width: 36
                                    height: 28
                                    verticalAlignment: Text.AlignVCenter
                                    text: "HZ"
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSecondary
                                }

                                Flow {
                                    width: parent.width - 36 - 8
                                    spacing: 6

                                    Repeater {
                                        model: card.off ? [] : page.refreshRates(card.modelData)

                                        delegate: Rectangle {
                                            id: rateButton
                                            required property var modelData
                                            property bool isPending: page.pendingRateMonitor === card.modelData.name && page.pendingRate > 0
                                            property bool current: isPending ? (Math.abs(modelData - page.pendingRate) < 0.05) : (Math.abs(modelData - card.modelData.refreshRate) < 0.05)

                                            width: 76
                                            height: 28
                                            radius: Theme.radius
                                            color: current ? Theme.alpha(Theme.accent, 0.16) : (rateMouse.containsMouse ? Theme.alpha(Theme.accent, 0.08) : "#00000000")
                                            border.width: current ? 1.5 : 1
                                            border.color: current ? Theme.accent : (rateMouse.containsMouse ? Theme.borderAccent : Theme.border)

                                            Text {
                                                anchors.centerIn: parent
                                                text: rateButton.modelData.toFixed(2)
                                                color: current ? Theme.accent : Theme.text
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSecondary
                                                font.bold: current
                                            }

                                            ControlArea {
                                                id: rateMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: page.setRefreshRate(card.modelData, rateButton.modelData)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 34
                radius: Theme.radius
                color: resetMouse.containsMouse ? Theme.alpha(Theme.accent, 0.08) : "#00000000"
                border.width: 1
                border.color: resetMouse.containsMouse ? Theme.borderAccent : Theme.border

                Text {
                    anchors.centerIn: parent
                    text: "Reset to config"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                    font.letterSpacing: 0
                }

                ControlArea {
                    id: resetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.resetToConfig()
                }
            }
        }

        ScrollBar.vertical: SettingsScrollBar {}
    }
}