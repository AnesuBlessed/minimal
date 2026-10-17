//@ pragma UseQApplication
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "."

ShellRoot {
    id: root
    Palette { id: theme }
    property string query: ""
    property string activeCategory: "All"
    property var results: []

    readonly property var categories: ["All", "Apps", "Windows", "Workspace", "System", "Media"]

    readonly property var defaultShortcuts: [
        // Apps & Popups
        { category: "Apps", icon: "󰀻", title: "Application Launcher", subtitle: "Open Quickshell bottom app launcher", keys: ["Super", "A"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/launcher.sh\""] },
        { category: "Apps", icon: "󰆍", title: "Terminal (Foot)", subtitle: "Launch fast Foot client terminal", keys: ["Super", "T"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/terminal.sh\""] },
        { category: "Apps", icon: "󰈹", title: "Web Browser", subtitle: "Launch default web browser", keys: ["Super", "B / F"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/open-app.sh\" browser"] },
        { category: "Apps", icon: "󰉋", title: "File Manager", subtitle: "Open file manager (Dolphin / Thunar)", keys: ["Super", "E"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/open-app.sh\" files"] },
        { category: "Apps", icon: "󰅌", title: "Clipboard History", subtitle: "Browse, search, and manage clipboard", keys: ["Super", "C"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/clipboard.sh\""] },
        { category: "Apps", icon: "󰸉", title: "Wallpaper Picker", subtitle: "Open wallpaper carousel & web search", keys: ["Super", "W"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/wallchange.sh\""] },
        { category: "Apps", icon: "󱊞", title: "USB Drive Menu", subtitle: "Browse or safely unmount removable drives", keys: ["Super", "U"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/usb-menu.sh\""] },
        { category: "Apps", icon: "󰌌", title: "Keybind Cheat-Sheet", subtitle: "Toggle this interactive shortcut reference", keys: ["Super", "/"], cmd: [] },

        // Windows
        { category: "Windows", icon: "󰅖", title: "Close Active Window", subtitle: "Gracefully close focused window", keys: ["Super", "Q"], cmd: ["hyprctl", "dispatch", "hl.dsp.window.close()"] },
        { category: "Windows", icon: "󰊓", title: "Fullscreen Window", subtitle: "Toggle fullscreen on focused window", keys: ["Super", "M / F11"], cmd: ["hyprctl", "dispatch", "hl.dsp.window.fullscreen()"] },
        { category: "Windows", icon: "󰙀", title: "Toggle Floating", subtitle: "Switch window between tiled and floating", keys: ["Super", "Shift", "F"], cmd: ["hyprctl", "dispatch", "hl.dsp.window.float({ action = \"toggle\" })"] },
        { category: "Windows", icon: "󰁌", title: "Focus Window", subtitle: "Move focus in arrow direction", keys: ["Super", "← ↓ ↑ →"], cmd: [] },
        { category: "Windows", icon: "󰆾", title: "Move Window Directionally", subtitle: "Swap/move tiled window in arrow direction", keys: ["Super", "Ctrl", "← ↓ ↑ →"], cmd: [] },
        { category: "Windows", icon: "󰁁", title: "Resize Active Window", subtitle: "Resize focused window by 30px steps", keys: ["Super", "Shift", "← ↓ ↑ →"], cmd: [] },
        { category: "Windows", icon: "󰍽", title: "Move / Resize with Mouse", subtitle: "Hold Super and drag with Left / Right click", keys: ["Super", "LMB / RMB"], cmd: [] },

        // Workspaces
        { category: "Workspace", icon: "󰧨", title: "Switch Workspace 1–9", subtitle: "Jump directly to workspace 1 through 9", keys: ["Super", "1 … 9"], cmd: [] },
        { category: "Workspace", icon: "󰆾", title: "Move Window to Workspace", subtitle: "Send active window to workspace 1–9", keys: ["Super", "Shift", "1 … 9"], cmd: [] },
        { category: "Workspace", icon: "󰘔", title: "Pocket Scratchpad", subtitle: "Toggle special pocket scratchpad overlay", keys: ["Super", "BackSpace"], cmd: ["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special(\"pocket\")"] },
        { category: "Workspace", icon: "󰞒", title: "Move to Pocket Scratchpad", subtitle: "Send active window to pocket scratchpad", keys: ["Super", "Shift", "BackSpace"], cmd: ["hyprctl", "dispatch", "hl.dsp.window.move({ workspace = \"special:pocket\" })"] },
        { category: "Workspace", icon: "󰹑", title: "Cycle Workspaces", subtitle: "Scroll wheel while holding Super", keys: ["Super", "Scroll"], cmd: [] },

        // System & Settings
        { category: "System", icon: "󰌾", title: "Lock Screen", subtitle: "Lock session immediately with Hyprlock", keys: ["Super", "L"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/lock.sh\""] },
        { category: "System", icon: "󰐥", title: "Power Menu", subtitle: "Open wlogout session power menu", keys: ["Super", "Esc"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/powermenu.sh\""] },
        { category: "System", icon: "󰑓", title: "Reload Desktop & Bar", subtitle: "Reload Hyprland config and Waybar in place", keys: ["Super", "R"], cmd: ["bash", "-c", "hyprctl reload && \"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/waybar.sh\" --reload"] },
        { category: "System", icon: "󰒓", title: "Control Center", subtitle: "Open unified quick settings (Wi-Fi, BT, Audio, Display)", keys: ["Super", "S"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/control-center.sh\""] },
        { category: "System", icon: "󰍹", title: "Display & Monitor Switcher", subtitle: "Configure multi-monitor layout, refresh rate, and scale", keys: ["Super", "P"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/monitors.sh\""] },
        { category: "System", icon: "󰖩", title: "Wi-Fi Manager", subtitle: "Scan, connect, hotspot, and manage saved networks", keys: ["Super", "N"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/control-center.sh\" wifi"] },
        { category: "System", icon: "󰂯", title: "Bluetooth Manager", subtitle: "Pair, connect, trust, and manage Bluetooth devices", keys: ["Super", "Shift", "B"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/control-center.sh\" bluetooth"] },
        { category: "System", icon: "󰕾", title: "Audio Mixer", subtitle: "Configure PipeWire output sinks and microphones", keys: ["Super", "V"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/control-center.sh\" audio"] },
        { category: "System", icon: "󰂛", title: "Toggle Do Not Disturb", subtitle: "Silence or resume desktop notifications", keys: ["Super", "Shift", "D"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/notifications.sh\" dnd"] },
        { category: "System", icon: "󰂚", title: "Dismiss / Recall Notification", subtitle: "Dismiss latest, dismiss all, or recall history", keys: ["Super", "Shift / Alt", "N"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/notifications.sh\" dismiss"] },

        // Media & Screenshots
        { category: "Media", icon: "󰹑", title: "Region Screenshot", subtitle: "Capture selected screen region to clipboard", keys: ["Print"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/screenshot.sh\" region"] },
        { category: "Media", icon: "󰏫", title: "Annotate Screenshot", subtitle: "Capture region and open in Satty editor", keys: ["Shift", "Print"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/screenshot.sh\" edit"] },
        { category: "Media", icon: "󰍹", title: "Full Screen Screenshot", subtitle: "Capture entire display to clipboard", keys: ["Super", "Print"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/screenshot.sh\" full"] },
        { category: "Media", icon: "󰑊", title: "Screen Recording", subtitle: "Start or stop region MP4 screen recording", keys: ["Super", "Shift", "R"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/screenshot.sh\" record"] },
        { category: "Media", icon: "󰈙", title: "Instant Region OCR", subtitle: "Extract text from screen region into clipboard", keys: ["Super", "Shift", "O"], cmd: ["bash", "-c", "\"${MINIMAL_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/minimal}/scripts/screenshot.sh\" ocr"] },
        { category: "Media", icon: "󰐎", title: "Play / Pause Media", subtitle: "Toggle active MPRIS media player", keys: ["Super", "Space"], cmd: ["playerctl", "play-pause"] },
        { category: "Media", icon: "󰕾", title: "Volume Up / Down / Mute", subtitle: "PipeWire audio control with Mako progress OSD", keys: ["XF86Audio", "Vol / Mute"], cmd: [] },
        { category: "Media", icon: "󰃠", title: "Screen Brightness", subtitle: "Backlight adjustment with safe 1% minimum", keys: ["XF86MonBrightness", "Up / Down"], cmd: [] }
    ]

    readonly property var shortcuts: {
        const raw = Quickshell.env("MINIMAL_KEYBINDS_JSON");
        if (raw && raw.trim() !== "") {
            try {
                const parsed = JSON.parse(raw);
                if (Array.isArray(parsed) && parsed.length > 0) return parsed;
            } catch (e) {}
        }
        return defaultShortcuts;
    }

    function score(text, needle) {
        text = text.toLowerCase();
        const direct = text.indexOf(needle);
        if (direct >= 0) return direct;
        let pos = -1, cost = 50;
        for (const letter of needle) {
            const next = text.indexOf(letter, pos + 1);
            if (next < 0) return -1;
            cost += next - pos - 1;
            pos = next;
        }
        return cost;
    }

    function refresh() {
        const needle = query.trim().toLowerCase();
        let matches = [];
        for (const item of shortcuts) {
            if (activeCategory !== "All" && item.category !== activeCategory) continue;
            const searchable = [item.title, item.subtitle, item.category, item.keys.join(" ")].join(" ");
            const rank = needle ? score(searchable, needle) : 0;
            if (rank >= 0) matches.push({ item: item, rank: rank });
        }
        if (needle) matches.sort((a, b) => a.rank - b.rank);
        results = matches.map(m => m.item);
        list.currentIndex = results.length ? 0 : -1;
    }

    function trigger(index) {
        if (index < 0 || index >= results.length) return;
        const item = results[index];
        if (item.cmd && item.cmd.length > 0) {
            Quickshell.execDetached(["bash", "-c", "sleep 0.05; exec \"$@\"", "--"].concat(item.cmd));
        }
        Qt.quit();
    }

    onQueryChanged: refresh()
    onActiveCategoryChanged: refresh()
    Component.onCompleted: refresh()

    PanelWindow {
        id: panel
        screen: Quickshell.screens.find(s => s.name === Quickshell.env("MINIMAL_POPUP_OUTPUT")) || Quickshell.screens[0]
        anchors.bottom: true
        implicitWidth: Math.min(620, screen.width - 24)
        implicitHeight: Math.min(460, screen.height - 48)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "minimal-keybinds"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        HyprlandFocusGrab {
            windows: [panel]
            active: true
            onCleared: Qt.quit()
        }

        Rectangle {
            anchors.fill: parent
            topLeftRadius: theme.panelRadius
            topRightRadius: theme.panelRadius
            color: theme.panel
            border.width: 1
            border.color: theme.border

            // Top centered handle
            Rectangle {
                width: 32; height: 3; radius: 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                y: 9
                color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.32)
            }

            // Search bar
            Rectangle {
                id: searchBox
                x: 12; y: 22
                width: parent.width - 24; height: 36
                radius: theme.controlRadius
                color: theme.control
                border.width: 1
                border.color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.10)

                Text {
                    x: 11; anchors.verticalCenter: parent.verticalCenter
                    text: "󰌌"; font.family: theme.fontFamily; font.pixelSize: 15
                    color: theme.accent
                }

                TextInput {
                    id: search
                    x: 34; width: parent.width - 110; height: parent.height
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: theme.fontFamily; font.pixelSize: theme.fontBody
                    color: theme.text; selectionColor: theme.selection
                    clip: true; focus: true; selectByMouse: true
                    onTextChanged: root.query = text
                    Component.onCompleted: forceActiveFocus()

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Search keybinds or actions…"; visible: !search.text
                        font: search.font; color: theme.muted
                    }

                    Keys.onEscapePressed: Qt.quit()
                    Keys.onReturnPressed: root.trigger(list.currentIndex)
                    Keys.onEnterPressed: root.trigger(list.currentIndex)
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onTabPressed: {
                        const idx = root.categories.indexOf(root.activeCategory);
                        root.activeCategory = root.categories[(idx + 1) % root.categories.length];
                    }
                }

                Text {
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.results.length + " binds"
                    font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary
                    color: theme.muted
                }
            }

            // Category filter pills
            Row {
                id: categoryBar
                x: 12; y: 66
                spacing: 6
                Repeater {
                    model: root.categories
                    delegate: Rectangle {
                        required property string modelData
                        readonly property bool active: root.activeCategory === modelData
                        width: catLabel.implicitWidth + 18
                        height: 24
                        radius: theme.controlRadius
                        color: active ? theme.accent : theme.control
                        border.width: 1
                        border.color: active ? theme.accent : Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

                        Text {
                            id: catLabel
                            anchors.centerIn: parent
                            text: modelData
                            font.family: theme.fontFamily
                            font.pixelSize: theme.fontSecondary
                            font.bold: active
                            color: active ? theme.base : theme.text
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activeCategory = modelData
                        }
                    }
                }
            }

            // Shortcut list
            ListView {
                id: list
                x: 8; y: 98
                width: parent.width - 16; height: parent.height - y - 8
                model: root.results
                clip: true
                spacing: 3
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationWraps: true
                highlightMoveDuration: 0
                property real lastMouseX: -1
                property real lastMouseY: -1
                ScrollBar.vertical: ScrollBar { width: 3; policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width; height: 42
                    radius: theme.controlRadius
                    color: ListView.isCurrentItem
                        ? theme.control
                        : hover.containsMouse
                            ? Qt.rgba(theme.selection.r, theme.selection.g, theme.selection.b, 0.45)
                            : "transparent"

                    // Category icon badge
                    Rectangle {
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        width: 28; height: 28
                        radius: theme.controlRadius
                        color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.14)
                        border.width: 1
                        border.color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.28)

                        Text {
                            anchors.centerIn: parent
                            text: row.modelData.icon
                            font.family: theme.fontFamily; font.pixelSize: 14
                            color: theme.accent
                        }
                    }

                    // Action title & subtitle
                    Column {
                        x: 44; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - keyRow.width - 64
                        spacing: 1

                        Text {
                            width: parent.width
                            text: row.modelData.title
                            textFormat: Text.PlainText; elide: Text.ElideRight
                            font.family: theme.fontFamily; font.pixelSize: theme.fontBody
                            font.bold: true
                            color: theme.text
                        }

                        Text {
                            width: parent.width
                            text: row.modelData.subtitle
                            textFormat: Text.PlainText; elide: Text.ElideRight
                            font.family: theme.fontFamily; font.pixelSize: theme.fontSecondary
                            color: theme.muted
                        }
                    }

                    // Keycap pills on the right
                    Row {
                        id: keyRow
                        anchors.right: parent.right; anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Repeater {
                            model: row.modelData.keys
                            delegate: Rectangle {
                                required property string modelData
                                width: keyText.implicitWidth + 14
                                height: 24
                                radius: Math.max(4, theme.controlRadius - 1)
                                color: theme.reading
                                border.width: 1
                                border.color: theme.border

                                Text {
                                    id: keyText
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.family: theme.fontFamily
                                    font.pixelSize: theme.fontSecondary
                                    font.bold: true
                                    color: theme.accent
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: (mouse) => {
                            const pt = mapToItem(list, mouse.x, mouse.y);
                            if (Math.abs(pt.x - list.lastMouseX) > 0.5 || Math.abs(pt.y - list.lastMouseY) > 0.5) {
                                list.lastMouseX = pt.x;
                                list.lastMouseY = pt.y;
                                list.currentIndex = row.index;
                            }
                        }
                        onClicked: root.trigger(row.index)
                    }
                }
            }

            Text {
                anchors.centerIn: list
                visible: root.results.length === 0
                text: "No matching shortcuts"; color: theme.muted
                font.family: theme.fontFamily; font.pixelSize: theme.fontBody
            }
        }
    }
}
