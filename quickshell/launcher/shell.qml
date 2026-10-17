//@ pragma UseQApplication
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "."

ShellRoot {
    id: root
    Palette { id: theme }
    property string query: ""
    property var entries: DesktopEntries.applications.values
    property var results: []
    property var searchIndex: []

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
    function rebuildIndex() {
        const rows = [];
        for (const app of (entries || [])) {
            if (!app || app.noDisplay) continue;
            const title = app.name || app.id || "";
            const keywords = Array.isArray(app.keywords) ? app.keywords.join(" ") : "";
            const categories = Array.isArray(app.categories) ? app.categories.join(" ") : "";
            const base = {app: app, action: null, title: title,
                icon: app.icon || "",
                search: [title, app.genericName || "", app.id || "", app.comment || "",
                         keywords, categories].join(" ").toLowerCase()};
            rows.push(base);
            for (const action of (app.actions || [])) {
                if (!action || !action.name) continue;
                rows.push({
                    app: app,
                    action: action,
                    title: title + " — " + action.name,
                    icon: action.icon || app.icon || "",
                    search: [title, action.name, app.genericName || "", app.id || ""].join(" ").toLowerCase()
                });
            }
        }
        // Index and alphabetical order are rebuilt only when the app list changes.
        rows.sort((a, b) => (a.title || "").localeCompare(b.title || ""));
        searchIndex = rows;
        refresh();
    }
    function refresh() {
        const needle = query.trim().toLowerCase();
        let matches = [];
        for (const row of searchIndex) {
            if (!needle && row.action) continue;
            const rank = needle ? score(row.search, needle) : 0;
            if (rank >= 0) matches.push({row: row, rank: rank});
        }
        if (needle) matches.sort((a, b) => a.rank - b.rank);
        results = matches.map(match => match.row);
        list.currentIndex = results.length ? 0 : -1;
    }
    function launch(index) {
        if (index < 0 || index >= results.length) return;
        const row = results[index];
        const target = row.action || row.app;
        if (!row.action && ["foot", "foot.desktop", "footclient", "footclient.desktop"].includes(row.app.id)) {
            Quickshell.execDetached({command: [Quickshell.shellDir + "/../../scripts/terminal.sh"],
                                    workingDirectory: row.app.workingDirectory});
        } else if (row.app.runInTerminal) {
            Quickshell.execDetached({command: [Quickshell.shellDir + "/../../scripts/terminal.sh"].concat(Array.from(target.command)),
                                    workingDirectory: row.app.workingDirectory});
        } else {
            target.execute();
        }
        Qt.quit();
    }
    onQueryChanged: refresh()
    onEntriesChanged: rebuildIndex()
    Component.onCompleted: rebuildIndex()

    PanelWindow {
        id: panel
        screen: Quickshell.screens.find(s => s.name === Quickshell.env("MINIMAL_LAUNCHER_OUTPUT")) || Quickshell.screens[0]
        anchors.bottom: true
        implicitWidth: Math.min(470, screen.width - 24)
        implicitHeight: Math.min(374, screen.height - 48)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "minimal-launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        HyprlandFocusGrab {
            windows: [panel]
            active: true
            onCleared: Qt.quit()
        }

        // Square bottom corners join the screen edge; only the top is rounded.
        Rectangle {
            anchors.fill: parent
            topLeftRadius: theme.panelRadius
            topRightRadius: theme.panelRadius
            color: theme.panel
            border.width: 1
            border.color: theme.border

            Rectangle {
                width: 32; height: 3; radius: 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                y: 9
                color: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.32)
            }
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
                    text: ""; font.family: theme.fontFamily; font.pixelSize: 13
                    color: theme.muted
                }
                TextInput {
                    id: search
                    x: 34; width: parent.width - 46; height: parent.height
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: theme.fontFamily; font.pixelSize: theme.fontBody
                    color: theme.text; selectionColor: theme.selection
                    clip: true; focus: true; selectByMouse: true
                    onTextChanged: root.query = text
                    Component.onCompleted: forceActiveFocus()
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Search apps"; visible: !search.text
                        font: search.font; color: theme.muted
                    }
                    Keys.onEscapePressed: Qt.quit()
                    Keys.onReturnPressed: root.launch(list.currentIndex)
                    Keys.onEnterPressed: root.launch(list.currentIndex)
                    Keys.onDownPressed: list.incrementCurrentIndex()
                    Keys.onUpPressed: list.decrementCurrentIndex()
                    Keys.onTabPressed: list.incrementCurrentIndex()
                }
            }
            ListView {
                id: list
                x: 8; y: 66
                width: parent.width - 16; height: parent.height - y - 8
                model: root.results
                clip: true
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
                    width: list.width; height: 37
                    radius: theme.controlRadius
                    color: ListView.isCurrentItem ? theme.control : hover.containsMouse ? Qt.rgba(theme.selection.r, theme.selection.g, theme.selection.b, 0.45) : "transparent"
                    Image {
                        id: icon
                        x: 9; anchors.verticalCenter: parent.verticalCenter
                        width: theme.appIcon; height: theme.appIcon
                        source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                        sourceSize.width: 54; sourceSize.height: 54
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    Text {
                        x: 47; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 59
                        text: row.modelData.title; textFormat: Text.PlainText; elide: Text.ElideRight
                        font.family: theme.fontFamily; font.pixelSize: theme.fontBody
                        color: theme.text
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
                        onClicked: root.launch(row.index)
                    }
                }
            }
            Text {
                anchors.centerIn: list
                visible: root.results.length === 0
                text: "No matching apps"; color: theme.muted
                font.pixelSize: theme.fontBody
            }
        }
    }
}
