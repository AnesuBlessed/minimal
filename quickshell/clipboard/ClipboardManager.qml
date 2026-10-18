import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "."

Item {
    id: window
    focus: true

    Caching { id: paths }

    // Qt already uses logical pixels; keep text consistent with Fuzzel and Foot.
    function s(val) { return Math.round(val); }

    Palette { id: theme }
    readonly property color base: theme.base
    readonly property color text: theme.text
    readonly property color muted: theme.muted
    readonly property color selection: theme.selection
    readonly property color border: theme.border
    readonly property color accent: theme.accent
    readonly property color accentSubtle: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.20)
    // Backward compatibility aliases
    readonly property color crust: theme.crust
    readonly property color subtext0: muted
    readonly property color surface0: selection
    readonly property color surface1: border
    readonly property color surface2: accentSubtle
    readonly property color mauve: accent

    property var allClips: []
    property string requestedQuery: ""
    property bool pendingSearch: false
    Timer {
        id: searchDebounce
        interval: 60
        onTriggered: window.reloadSearch()
    }
    function reloadSearch() {
        if (clipFetcher.running || clipboardAction.running) { pendingSearch = true; return; }
        pendingSearch = false;
        requestedQuery = searchInput.text;
        requestedOffset = 0;
        currentOffset = 0;
        hasMore = true;
        isLoading = true;
        clipFetcher.running = true;
    }

    // Pagination properties
    property int currentOffset: 0
    // Offset actually passed to the in-flight fetch. Kept separate from
    // currentOffset so a response can be routed by the page it belongs to.
    property int requestedOffset: 0
    property bool pendingMore: false
    property int fetchLimit: 24
    property bool isLoading: true
    property bool hasMore: true

    // Global state
    property int navDuration: 0
    property bool previewMode: false
    property bool previewAnimationDone: false
    property string fullTextPreview: ""
    property int pendingIndex: -1

    property real layoutWidth: width
    property real layoutHeight: height

    // Startup state to prevent accordion layout shifts
    property bool isInitialLoad: true

    onPreviewModeChanged: {
        if (!previewMode) {
            fullTextPreview = "";
            previewAnimationDone = false;
        }
    }

    Process {
        id: fullTextFetcher
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                window.fullTextPreview = this.text;
            }
        }
    }

    function updatePreviewText() {
        window.fullTextPreview = "";
        fullTextFetcher.running = false;
        let item = clipModel.get(clipList.currentIndex);
        if (item && item.type === "text") {
            fullTextFetcher.command = ["python3", Quickshell.shellDir + "/clip_fetcher.py", "--text", item.id.toString()];
            fullTextFetcher.running = true;
        }
    }

    Process {
        id: clipFetcher
        running: window.visible
        command: ["python3", Quickshell.shellDir + "/clip_fetcher.py", window.requestedOffset, window.fetchLimit, paths.getCacheDir("clipboard"), window.requestedQuery]
        stdout: StdioCollector { id: clipOutput }
        onExited: (exitCode, exitStatus) => {
            window.isInitialLoad = false;
            if (window.pendingSearch || window.requestedQuery !== searchInput.text) {
                window.isLoading = false;
                Qt.callLater(window.reloadSearch);
                return;
            }
            if (clipboardAction.running) { window.isLoading = false; return; }
            try {
                const items = JSON.parse(clipOutput.text);
                if (exitCode !== 0 || !Array.isArray(items)) {
                    window.pendingMore = false;
                    window.isLoading = false;
                    Quickshell.execDetached(["notify-send", "Clipboard unavailable", "Could not load or search history. Please retry."]);
                    return;
                }
                window.currentOffset = window.requestedOffset + items.length;
                window.hasMore = items.length === window.fetchLimit;
                if (window.requestedOffset === 0) {
                    window.allClips = items;
                    window.filterClips();
                } else {
                    window.appendClips(items);
                }
                window.isLoading = false;
                if (window.pendingMore) {
                    window.pendingMore = false;
                    Qt.callLater(window.loadMore);
                }
            } catch (error) {
                window.isLoading = false;
                window.pendingMore = false;
                console.warn("Clipboard fetch failed:", error);
            }
        }
    }

    Process {
        id: clipboardAction
        property string action: ""
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("Clipboard action failed:", action);
                return;
            }
            if (action === "copy") {
                Qt.quit();
            } else {
                window.allClips = [];
                clipModel.clear();
                window.currentOffset = 0;
                window.requestedOffset = 0;
                window.pendingMore = false;
                window.hasMore = true;
                window.isLoading = true;
                clipFetcher.running = true;
            }
        }
    }

    function mutateClipboard(action, id) {
        if (clipboardAction.running) return;
        const args = [paths.minimalRoot + "/scripts/clipboard-action.sh", action];
        if (action !== "wipe") {
            if (!/^[0-9]+$/.test(String(id))) return;
            args.push(String(id));
        }
        clipboardAction.action = action;
        clipboardAction.command = args;
        clipboardAction.running = true;
        clipFetcher.running = false;
    }

    ListModel { id: clipModel }

    function loadMore() {
        if (!hasMore || clipboardAction.running) return;
        if (isLoading || clipFetcher.running) {
            pendingMore = true;
            return;
        }
        requestedOffset = currentOffset;
        isLoading = true;
        clipFetcher.running = true;
    }

    function appendClips(newItems) {
        for (let i = 0; i < newItems.length; i++) {
            allClips.push(newItems[i]);
            clipModel.append(newItems[i]);
        }

        if (window.pendingIndex !== -1) {
            if (window.pendingIndex < clipModel.count) {
                clipList.currentIndex = window.pendingIndex;
            } else {
                clipList.currentIndex = clipModel.count - 1;
            }
            window.pendingIndex = -1;
        }
    }

    function filterClips() {
        clipList.currentIndex = -1;
        clipList.positionViewAtBeginning();
        clipModel.clear();

        for (let i = 0; i < allClips.length; i++) {
            clipModel.append(allClips[i]);
        }

        if (clipModel.count > 0) {
            clipList.currentIndex = 0;
        }
    }

    function copyToClipboard(id) {
        mutateClipboard("copy", id);
    }

    Component.onCompleted: {
        searchInput.forceActiveFocus();
    }

    Connections {
        target: window
        function onVisibleChanged() {
            if (window.visible) {
                if (window.allClips.length === 0) {
                    window.isInitialLoad = true;
                }

                searchInput.forceActiveFocus();
                introPhaseAnim.restart();
                window.navDuration = 0;
                window.previewMode = false;
                window.previewAnimationDone = false;
                window.fullTextPreview = "";
                window.pendingIndex = -1;

                if (!clipFetcher.running) {
                    window.currentOffset = 0;
                    window.requestedOffset = 0;
                    window.hasMore = true;
                    window.isLoading = true;
                    clipFetcher.running = true;
                }
            } else {
                searchInput.text = "";
                window.pendingIndex = -1;

                window.filterClips();
                if (clipModel.count > 0) {
                    clipList.currentIndex = 0;
                    clipList.positionViewAtBeginning();
                }
            }
        }
    }

    property real introPhase: 0
    NumberAnimation on introPhase {
        id: introPhaseAnim
        from: 0; to: 1; duration: theme.duration; easing.type: Easing.OutExpo; running: window.visible
    }

    Rectangle {
        id: mainBg
        MouseArea { anchors.fill: parent }
        width: layoutWidth

        property real searchHeight: window.s(76)
        property real footerHeight: window.s(34)
        property real separatorHeight: 1

        property int cols: width < 560 ? 2 : 3
        property real cellH: window.s(126)

        property real animatedListHeight: Math.max(80, layoutHeight - searchHeight - separatorHeight - animatedMargins - footerHeight)
        property real animatedMargins: window.s(20)

        height: layoutHeight

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        topLeftRadius: theme.panelRadius
        topRightRadius: theme.panelRadius
        color: theme.reading
        border.color: theme.border
        border.width: 1
        clip: true

        transform: Translate { y: (window.introPhase - 1) * window.s(8) }
        opacity: window.introPhase

        Rectangle {
            id: headerArea
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: mainBg.searchHeight
            color: "transparent"

            Rectangle {
                width: 32; height: 3; radius: 1.5
                anchors.horizontalCenter: parent.horizontalCenter
                y: 9; color: theme.muted; opacity: 0.4
            }
            Rectangle {
                x: theme.spaceLarge; y: 22
                width: parent.width - theme.spaceLarge * 2; height: 40
                radius: theme.controlRadius; color: theme.control
            }
            RowLayout {
                anchors.fill: parent
                anchors.margins: theme.spaceLarge
                anchors.topMargin: 22
                anchors.bottomMargin: 14
                anchors.leftMargin: window.s(20)
                anchors.rightMargin: window.s(20)
                spacing: window.s(15)

                Item {
                    width: window.s(18)
                    height: window.s(18)

                    Text {
                        anchors.centerIn: parent
                        text: "󰅌"
                        font.family: theme.fontFamily
                        font.pixelSize: window.s(18)
                        color: searchInput.activeFocus ? theme.accent : theme.muted

                        opacity: !window.previewMode ? 1 : 0
                        scale: !window.previewMode ? 1 : 0.5
                        rotation: !window.previewMode ? 0 : -90

                        Behavior on opacity { NumberAnimation { duration: theme.duration; easing.type: Easing.InOutQuad } }
                        Behavior on scale { NumberAnimation { duration: theme.duration; easing.type: Easing.OutCubic } }
                        Behavior on rotation { NumberAnimation { duration: theme.duration; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "󰈈"
                        font.family: theme.fontFamily
                        font.pixelSize: window.s(18)
                        color: theme.accent

                        opacity: window.previewMode ? 1 : 0
                        scale: window.previewMode ? 1 : 0.5
                        rotation: window.previewMode ? 0 : 90

                        Behavior on opacity { NumberAnimation { duration: theme.duration; easing.type: Easing.InOutQuad } }
                        Behavior on scale { NumberAnimation { duration: theme.duration; easing.type: Easing.OutCubic } }
                        Behavior on rotation { NumberAnimation { duration: theme.duration; easing.type: Easing.OutCubic } }
                    }
                }

                TextField {
                    id: searchInput
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    background: Item {}
                    color: window.text
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontBody

                    placeholderText: "Search clipboard"
                    placeholderTextColor: theme.muted

                    verticalAlignment: TextInput.AlignVCenter
                    focus: true

                    onTextChanged: {
                        if (window.previewMode) { window.previewMode = false; }
                        window.pendingIndex = -1;
                        searchDebounce.restart();
                    }

                    Keys.onTabPressed: {
                        if (clipModel.count > 0) {
                            window.previewMode = !window.previewMode;
                            if (window.previewMode) {
                                window.updatePreviewText();
                            }
                        }
                        event.accepted = true;
                    }

                    Keys.onRightPressed: {
                        window.previewMode = false;
                        window.navDuration = 120;
                        window.pendingIndex = -1;

                        let targetIdx = clipList.currentIndex + 1;
                        if (targetIdx < clipModel.count) {
                            clipList.currentIndex = targetIdx;
                        } else if (window.hasMore) {
                            window.pendingIndex = targetIdx;
                            window.loadMore();
                        }
                        event.accepted = true;
                    }

                    Keys.onLeftPressed: {
                        window.previewMode = false;
                        window.navDuration = 120;
                        window.pendingIndex = -1;

                        if (clipList.currentIndex > 0) { clipList.currentIndex--; }
                        event.accepted = true;
                    }

                    Keys.onDownPressed: {
                        if (window.previewMode && textPreviewFlickable.visible) {
                            textPreviewFlickable.contentY = Math.min(textPreviewFlickable.contentY + window.s(60), Math.max(0, textPreviewFlickable.contentHeight - textPreviewFlickable.height));
                        } else {
                            window.previewMode = false;
                            window.navDuration = 120;
                            window.pendingIndex = -1;

                            let targetIdx = clipList.currentIndex < 0 ? 0 : clipList.currentIndex + mainBg.cols;
                            if (targetIdx < clipModel.count) {
                                clipList.currentIndex = targetIdx;
                            } else if (window.hasMore) {
                                window.pendingIndex = targetIdx;
                                window.loadMore();
                            } else {
                                clipList.currentIndex = clipModel.count - 1;
                            }
                        }
                        event.accepted = true;
                    }

                    Keys.onUpPressed: {
                        if (window.previewMode && textPreviewFlickable.visible) {
                            textPreviewFlickable.contentY = Math.max(textPreviewFlickable.contentY - window.s(60), 0);
                        } else {
                            window.previewMode = false;
                            window.navDuration = 120;
                            window.pendingIndex = -1;

                            if (clipList.currentIndex - mainBg.cols >= 0) { clipList.currentIndex -= mainBg.cols; }
                        }
                        event.accepted = true;
                    }

                    Keys.onReturnPressed: {
                        if (clipList.currentIndex >= 0 && clipList.currentIndex < clipModel.count) {
                            copyToClipboard(clipModel.get(clipList.currentIndex).id);
                        }
                        event.accepted = true;
                    }

                    Keys.onEscapePressed: {
                        if (window.previewMode) {
                            window.previewMode = false;
                        } else {
                            Qt.quit();
                        }
                        event.accepted = true;
                    }
                }

                Rectangle {
                    width: window.s(32)
                    height: window.s(32)
                    radius: window.s(8)
                    color: clearMa.containsMouse ? theme.accent : Qt.rgba(theme.selection.r, theme.selection.g, theme.selection.b, 0.4)

                    Text {
                        anchors.centerIn: parent
                        text: "󰃢"
                        font.family: theme.fontFamily
                        font.pixelSize: theme.fontBody
                        color: clearMa.containsMouse ? theme.base : window.text
                    }
                    MouseArea {
                        id: clearMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            window.mutateClipboard("wipe", "");
                        }
                    }
                }

            }
        }

        Rectangle {
            id: separatorLine
            anchors.top: headerArea.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: mainBg.separatorHeight
            color: Qt.rgba(theme.border.r, theme.border.g, theme.border.b, 0.5)
        }

        GridView {
            id: clipList
            anchors.top: separatorLine.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: mainBg.animatedMargins / 2
            anchors.bottomMargin: mainBg.animatedMargins / 2
            anchors.leftMargin: window.s(10)
            anchors.rightMargin: window.s(10)
            height: mainBg.animatedListHeight

            clip: true
            model: clipModel

            cellWidth: Math.floor((mainBg.width - window.s(20)) / mainBg.cols)
            cellHeight: mainBg.cellH

            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds

            highlightFollowsCurrentItem: false

            populate: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: theme.duration }
            }

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: theme.duration }
            }

            onContentYChanged: {
                if (contentY + height >= contentHeight - window.s(80)) {
                    window.loadMore();
                }
            }

            Behavior on contentY {
                enabled: window.navDuration > 0
                NumberAnimation { duration: theme.duration; easing.type: Easing.OutExpo }
            }

            onCurrentIndexChanged: {
                if (currentIndex >= 0 && clipList.model !== null) {
                    if (currentIndex >= clipModel.count - (mainBg.cols * 2)) {
                        window.loadMore();
                    }

                    let row = Math.floor(currentIndex / mainBg.cols);
                    let targetTop = row * mainBg.cellH;
                    let targetBottom = targetTop + mainBg.cellH;

                    if (window.navDuration > 0) {
                        if (targetTop < contentY) {
                            contentY = targetTop;
                        } else if (targetBottom > contentY + height) {
                            contentY = targetBottom - height;
                        }
                    } else {
                        positionViewAtIndex(currentIndex, GridView.Contain);
                    }
                }
            }

            ScrollBar.vertical: ScrollBar {
                active: true
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle {
                    implicitWidth: window.s(4)
                    radius: window.s(2)
                    color: window.accentSubtle
                    opacity: 0.5
                }
            }

            highlight: Item {
                z: 0
                Rectangle {
                    id: activeHighlight
                    width: clipList.cellWidth - window.s(10)
                    height: clipList.cellHeight - window.s(10)
                    radius: window.s(8)
                    color: theme.selection
                    border.color: window.accentSubtle
                    border.width: 1

                    property int curIdx: clipList.currentIndex
                    property real targetX: curIdx === -1 || clipList.model === null ? 0 : (curIdx % mainBg.cols) * clipList.cellWidth
                    property real targetY: curIdx === -1 || clipList.model === null ? 0 : Math.floor(curIdx / mainBg.cols) * clipList.cellHeight

                    Behavior on x { NumberAnimation { duration: window.navDuration > 0 ? window.navDuration : 120; easing.type: Easing.OutExpo } }
                    Behavior on y { NumberAnimation { duration: window.navDuration > 0 ? window.navDuration : 120; easing.type: Easing.OutExpo } }

                    x: targetX + window.s(5)
                    y: targetY + window.s(5)
                    opacity: clipList.count > 0 && clipList.currentIndex >= 0 && clipList.model !== null ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: theme.duration } }
                }
            }

            delegate: Item {
                id: delegateRoot
                width: clipList.cellWidth
                height: clipList.cellHeight

                z: index === clipList.currentIndex ? 50 : 1

                Rectangle {
                    id: cardBg
                    x: window.s(5)
                    y: window.s(5)
                    width: parent.width - window.s(10)
                    height: parent.height - window.s(10)

                    radius: window.s(8)

                    color: index === clipList.currentIndex ? "transparent" : ma.containsMouse ? theme.control : theme.reading
                    Behavior on color { ColorAnimation { duration: theme.duration; easing.type: Easing.OutSine } }

                    Rectangle {
                        z: 2
                        x: window.s(8)
                        y: window.s(8)
                        width: window.s(22)
                        height: window.s(22)
                        radius: window.s(6)

                        color: index === clipList.currentIndex ? theme.base : Qt.rgba(theme.selection.r, theme.selection.g, theme.selection.b, 0.85)

                        Text {
                            anchors.centerIn: parent
                            text: (index + 1)
                            font.family: theme.fontFamily
                            font.pixelSize: window.s(11)
                            font.weight: Font.Bold
                            color: index === clipList.currentIndex ? theme.accent : window.text
                        }
                    }

                    Rectangle {
                        z: 10
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: window.s(8)
                        width: window.s(22)
                        height: window.s(22)
                        radius: window.s(6)
                        color: deleteMa.containsMouse ? theme.accent : Qt.rgba(theme.selection.r, theme.selection.g, theme.selection.b, 0.7)

                        Text {
                            anchors.centerIn: parent
                            text: "󰅖"
                            font.family: theme.fontFamily
                            font.pixelSize: window.s(12)
                            color: deleteMa.containsMouse ? theme.base : window.text
                        }
                        MouseArea {
                            id: deleteMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                window.mutateClipboard("delete", model.id);
                            }
                        }
                    }


                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: window.s(4)

                        visible: model.type === "image"
                        color: "transparent"
                        radius: window.s(6)
                        clip: true

                        Image {
                    sourceSize.width: 384
                    sourceSize.height: 256
                            anchors.fill: parent
                            source: model.type === "image" ? "file://" + model.content : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true
                            smooth: true
                            mipmap: true
                        }
                    }

                    Item {
                        anchors.fill: parent
                        anchors.margins: window.s(12)
                        anchors.topMargin: window.s(36)
                        visible: model.type === "text"
                        clip: true

                        Text {
                            anchors.fill: parent
                            text: model.content
                            font.family: theme.fontFamily
                            font.pixelSize: window.s(13)
                            font.weight: Font.Normal
                            color: window.text
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignTop
                            maximumLineCount: 4

                            id: clipContentText
                            textFormat: Text.PlainText
                            Behavior on color { ColorAnimation { duration: theme.duration; easing.type: Easing.OutExpo } }
                        }
                    }

                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: !window.previewMode
                        enabled: !window.previewMode
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            window.navDuration = 120;
                            clipList.currentIndex = index;

                            if (mouse.button === Qt.RightButton) {
                                window.previewMode = true;
                                window.updatePreviewText();
                            } else {
                                copyToClipboard(model.id);
                            }
                        }
                    }
                }
            }
        }

        Text {
            anchors.centerIn: clipList
            visible: clipModel.count === 0
            text: window.isLoading ? "Loading clipboard…" : (searchInput.text.length ? "No matching entries" : "Your clipboard history is empty")
            color: theme.muted
            font.family: theme.fontFamily
            font.pixelSize: 13
        }

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            height: mainBg.footerHeight
            Text {
                text: "Enter  Copy    Tab  Preview    Esc  Close"
                color: theme.muted
                font.family: theme.fontFamily
                font.pixelSize: 10
                Layout.fillWidth: true
            }
            Text {
                text: clipModel.count + (window.hasMore ? "+" : "") + " items"
                color: theme.muted
                font.family: theme.fontFamily
                font.pixelSize: 10
            }
        }

        // FULL SCREEN PREVIEW OVERLAY
        Rectangle {
            id: previewMorph
            z: 100

            property var curItem: clipList.currentIndex >= 0 && clipModel.count > 0 ? clipModel.get(clipList.currentIndex) : null
            property int curIdx: clipList.currentIndex !== -1 ? clipList.currentIndex : 0

            property real gridX: window.s(10)
            property real gridY: mainBg.searchHeight + mainBg.separatorHeight + mainBg.animatedMargins / 2
            property real gridW: mainBg.width - window.s(20)
            property real gridH: mainBg.animatedListHeight

            property real startX: gridX + (curIdx % mainBg.cols) * clipList.cellWidth + window.s(5)
            property real startY: gridY + Math.floor(curIdx / mainBg.cols) * clipList.cellHeight - clipList.contentY + window.s(5)
            property real startW: clipList.cellWidth - window.s(10)
            property real startH: clipList.cellHeight - window.s(10)

            color: theme.base
            border.color: theme.accent
            border.width: window.previewMode ? 1 : 0
            Behavior on border.width { NumberAnimation { duration: theme.duration } }
            clip: true

            Image {
                    sourceSize.width: 1280
                    sourceSize.height: 1280
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: window.s(20)

                source: (previewMorph.curItem && previewMorph.curItem.type === "image") ? "file://" + previewMorph.curItem.content : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: previewMorph.curItem && previewMorph.curItem.type === "image"

                opacity: window.previewMode ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: theme.duration;  } }
            }

            Flickable {
                id: textPreviewFlickable
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: window.s(20)

                contentWidth: width
                contentHeight: textPreviewContent.paintedHeight
                clip: true

                Behavior on contentY { NumberAnimation { duration: theme.duration; easing.type: Easing.OutCubic } }

                visible: previewMorph.curItem && previewMorph.curItem.type === "text"
                opacity: window.previewMode ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: theme.duration;  } }

                TextEdit {
                    id: textPreviewContent
                    textFormat: TextEdit.PlainText
                    width: parent.width

                    text: {
                        if (!window.previewMode || !previewMorph.curItem || previewMorph.curItem.type !== "text") return "";

                        if (window.fullTextPreview !== "") {
                            if (!window.previewAnimationDone && window.fullTextPreview.length > 3000) {
                                return window.fullTextPreview.substring(0, 3000);
                            }
                            return window.fullTextPreview;
                        }

                        return previewMorph.curItem.content;
                    }

                    color: window.text
                    font.family: theme.fontFamily
                    font.pixelSize: theme.fontBody
                    wrapMode: TextEdit.Wrap
                    readOnly: true
                    selectByMouse: true
                    selectionColor: window.accentSubtle
                    selectedTextColor: theme.accent
                }
            }

            states: [
                State {
                    name: "hidden"
                    when: !window.previewMode
                    PropertyChanges {
                        target: previewMorph;
                        opacity: 0;
                        x: previewMorph.startX;
                        y: previewMorph.startY;
                        width: previewMorph.startW;
                        height: previewMorph.startH;
                        radius: window.s(8)
                    }
                },
                State {
                    name: "visible"
                    when: window.previewMode
                    PropertyChanges {
                        target: previewMorph;
                        opacity: 1;
                        x: previewMorph.gridX;
                        y: previewMorph.gridY;
                        width: previewMorph.gridW;
                        height: previewMorph.gridH;
                        radius: window.s(12)
                    }
                }
            ]

            transitions: [
                Transition {
                    from: "hidden"; to: "visible"
                    SequentialAnimation {
                        ParallelAnimation {
                            NumberAnimation { target: previewMorph; property: "opacity"; duration: 50 }
                            NumberAnimation { properties: "x,y,width,height,radius"; duration: theme.duration; easing.type: Easing.OutExpo }
                        }
                        ScriptAction { script: { window.previewAnimationDone = true; } }
                    }
                },
                Transition {
                    from: "visible"; to: "hidden"
                    ParallelAnimation {
                        NumberAnimation { properties: "x,y,width,height,radius"; duration: theme.duration; easing.type: Easing.OutExpo }
                        SequentialAnimation {
                            PauseAnimation { duration: 20 }
                            NumberAnimation { target: previewMorph; property: "opacity"; to: 0; duration: 100 }
                        }
                    }
                }
            ]
        }
    }
}
