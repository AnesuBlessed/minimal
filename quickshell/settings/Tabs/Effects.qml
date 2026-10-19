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

    property bool blurEnabled: false
    property bool animationsEnabled: true
    property bool nightLightEnabled: false
    property int temperature: 4500
    property string launcherPreference: "fuzzel"

    function refresh() {
        if (!pEffectsGet.running) pEffectsGet.running = true;
    }

    property var pendingChanges: []

    function applyNext() {
        if (pEffectsSet.running || pendingChanges.length === 0) return;
        var next = pendingChanges.shift();
        pEffectsSet.command = ["bash", Quickshell.shellDir + "/../../scripts/effects-config.sh", "set", next.key, String(next.value)];
        pEffectsSet.running = true;
    }

    function setOption(key, val) {
        // Keep only the latest value for a slider while a previous change finishes.
        pendingChanges = pendingChanges.filter(function(change) { return change.key !== key; });
        pendingChanges.push({key: key, value: val});
        applyNext();
    }

    Component.onCompleted: page.refresh()

    Process {
        id: pEffectsGet
        command: ["bash", Quickshell.shellDir + "/../../scripts/effects-config.sh", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text.trim());
                    page.blurEnabled = Boolean(data.blur);
                    page.animationsEnabled = Boolean(data.animations);
                    page.nightLightEnabled = Boolean(data.night_light);
                    page.temperature = parseInt(data.temperature) || 4500;
                    page.launcherPreference = data.launcher || "fuzzel";
                } catch (e) {}
            }
        }
    }

    Process {
        id: pEffectsSet
        stderr: StdioCollector { id: actionError }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                Quickshell.execDetached(["notify-send", "Minimal settings", actionError.text.trim() || "Could not apply the change"]);
                page.refresh();
            }
            Qt.callLater(page.applyNext);
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text.trim());
                    page.blurEnabled = Boolean(data.blur);
                    page.animationsEnabled = Boolean(data.animations);
                    page.nightLightEnabled = Boolean(data.night_light);
                    page.temperature = parseInt(data.temperature) || 4500;
                    page.launcherPreference = data.launcher || "fuzzel";
                } catch (e) {}
            }
        }
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

            // RENDERING & COMPOSITOR SECTION
            Text {
                text: "Rendering & Compositor"
                color: Theme.text
                topPadding: 4
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
            }

            // Blur Card
            Rectangle {
                width: parent.width
                height: 56
                radius: Theme.radius
                color: page.blurEnabled ? Theme.tint(Theme.accent, 0.08) : Theme.tint("#ffffff", 0.03)
                border.width: 1
                border.color: page.blurEnabled ? Theme.borderAccent : Theme.border

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.right: blurSwitch.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Text {
                        text: "󰂵"
                        font.family: Theme.iconFont
                        font.pixelSize: 18
                        color: page.blurEnabled ? Theme.accent : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "Frosted Glass Blur"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                        Text {
                            text: page.blurEnabled ? "Multi-pass blur enabled (higher GPU & power load)" : "Blur disabled (cool thermals & battery saving)"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSecondary
                        }
                    }
                }

                Rectangle {
                    id: blurSwitch
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44; height: 24; radius: 12
                    color: page.blurEnabled ? Theme.accent : Theme.tint("#ffffff", 0.1)
                    border.width: 1
                    border.color: page.blurEnabled ? Theme.borderAccent : Theme.borderStrong

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Rectangle {
                        width: 18; height: 18; radius: 9
                        color: page.blurEnabled ? "#ffffff" : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                        x: page.blurEnabled ? parent.width - width - 3 : 3
                        Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                    }
                }

                ControlArea {
                    anchors.fill: parent
                    onClicked: {
                        page.blurEnabled = !page.blurEnabled;
                        page.setOption("blur", page.blurEnabled);
                    }
                }
            }

            // Window Animations Card
            Rectangle {
                width: parent.width
                height: 56
                radius: Theme.radius
                color: page.animationsEnabled ? Theme.tint(Theme.accent, 0.08) : Theme.tint("#ffffff", 0.03)
                border.width: 1
                border.color: page.animationsEnabled ? Theme.borderAccent : Theme.border

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.right: animSwitch.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Text {
                        text: "󰑮"
                        font.family: Theme.iconFont
                        font.pixelSize: 18
                        color: page.animationsEnabled ? Theme.accent : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "Window Animations"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                        Text {
                            text: page.animationsEnabled ? "Smooth microSnap curves on open/close/workspace" : "Animations off for 0ms instant responsiveness"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSecondary
                        }
                    }
                }

                Rectangle {
                    id: animSwitch
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44; height: 24; radius: 12
                    color: page.animationsEnabled ? Theme.accent : Theme.tint("#ffffff", 0.1)
                    border.width: 1
                    border.color: page.animationsEnabled ? Theme.borderAccent : Theme.borderStrong

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Rectangle {
                        width: 18; height: 18; radius: 9
                        color: page.animationsEnabled ? "#ffffff" : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                        x: page.animationsEnabled ? parent.width - width - 3 : 3
                        Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                    }
                }

                ControlArea {
                    anchors.fill: parent
                    onClicked: {
                        page.animationsEnabled = !page.animationsEnabled;
                        page.setOption("animations", page.animationsEnabled);
                    }
                }
            }

            // APP LAUNCHER PREFERENCE SECTION
            Text {
                text: "Application Launcher"
                color: Theme.text
                topPadding: 8
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
            }

            Row {
                width: parent.width
                spacing: 10

                // Fuzzel Option
                Rectangle {
                    width: (parent.width - 10) / 2
                    height: 60
                    radius: Theme.radius
                    property bool selected: page.launcherPreference === "fuzzel"
                    color: selected ? Theme.tint(Theme.accent, 0.12) : Theme.tint("#ffffff", 0.03)
                    border.width: 1
                    border.color: selected ? Theme.borderAccent : Theme.border

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        Text {
                            text: "󰌌"
                            font.family: Theme.iconFont
                            font.pixelSize: 20
                            color: parent.parent.selected ? Theme.accent : Theme.textDim
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: "Fuzzel (Recommended)"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Text {
                                text: "Instant launch, 0 CPU, native C"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSecondary
                            }
                        }
                    }

                    ControlArea {
                        anchors.fill: parent
                        onClicked: {
                            page.launcherPreference = "fuzzel";
                            page.setOption("launcher", "fuzzel");
                        }
                    }
                }

                // Quickshell Option
                Rectangle {
                    width: (parent.width - 10) / 2
                    height: 60
                    radius: Theme.radius
                    property bool selected: page.launcherPreference === "quickshell"
                    color: selected ? Theme.tint(Theme.accent, 0.12) : Theme.tint("#ffffff", 0.03)
                    border.width: 1
                    border.color: selected ? Theme.borderAccent : Theme.border

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        Text {
                            text: "󰍜"
                            font.family: Theme.iconFont
                            font.pixelSize: 20
                            color: parent.parent.selected ? Theme.accent : Theme.textDim
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: "Quickshell"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Text {
                                text: "Interactive card popup (Qt6)"
                                color: Theme.textDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSecondary
                            }
                        }
                    }

                    ControlArea {
                        anchors.fill: parent
                        onClicked: {
                            page.launcherPreference = "quickshell";
                            page.setOption("launcher", "quickshell");
                        }
                    }
                }
            }

            // NIGHT LIGHT SECTION
            Text {
                text: "Night Light (Blue Light Filter)"
                color: Theme.text
                topPadding: 8
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.bold: true
            }

            // Night Light Toggle Card
            Rectangle {
                width: parent.width
                height: 56
                radius: Theme.radius
                color: page.nightLightEnabled ? Theme.tint(Theme.accent, 0.08) : Theme.tint("#ffffff", 0.03)
                border.width: 1
                border.color: page.nightLightEnabled ? Theme.borderAccent : Theme.border

                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.right: nlSwitch.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Text {
                        text: "󰖔"
                        font.family: Theme.iconFont
                        font.pixelSize: 18
                        color: page.nightLightEnabled ? Theme.accent : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "Blue Light Filter"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                        Text {
                            text: page.nightLightEnabled ? "Display colors shifted warm via hyprsunset" : "Standard 6500K daylight color profile"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSecondary
                        }
                    }
                }

                Rectangle {
                    id: nlSwitch
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44; height: 24; radius: 12
                    color: page.nightLightEnabled ? Theme.accent : Theme.tint("#ffffff", 0.1)
                    border.width: 1
                    border.color: page.nightLightEnabled ? Theme.borderAccent : Theme.borderStrong

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }

                    Rectangle {
                        width: 18; height: 18; radius: 9
                        color: page.nightLightEnabled ? "#ffffff" : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                        x: page.nightLightEnabled ? parent.width - width - 3 : 3
                        Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                    }
                }

                ControlArea {
                    anchors.fill: parent
                    onClicked: {
                        page.nightLightEnabled = !page.nightLightEnabled;
                        page.setOption("night_light", page.nightLightEnabled);
                    }
                }
            }

            // Temperature Slider Card (when night light is enabled)
            Rectangle {
                width: parent.width
                height: 64
                radius: Theme.radius
                color: Theme.tint("#ffffff", 0.03)
                border.width: 1
                border.color: Theme.border
                visible: page.nightLightEnabled

                Slider {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Color Warmth"
                    icon: "󰖨"
                    resettable: true
                    resetValue: 0.55
                    displayText: page.temperature + "K (" + (page.temperature <= 3500 ? "Candle" : page.temperature <= 4500 ? "Warm Amber" : "Soft") + ")"
                    // Range: 2500K to 6000K
                    value: (page.temperature - 2500) / 3500
                    onMoved: v => {
                        var k = Math.round(2500 + (v * 3500));
                        page.temperature = k;
                    }
                    onCommitted: v => {
                        var k = Math.round(2500 + (v * 3500));
                        page.temperature = k;
                        page.setOption("temperature", k);
                    }
                }
            }
        }
    }
}
