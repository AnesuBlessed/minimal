import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell.Wayland

PanelWindow {
    id: main

    // ---- Settings ----
    property int animDuration: 180
    property real zoomScale: 0.8
    property real edgeScale: 0.3
    property real skewFactor: -0.2
    property int baseSpacing: 10
    property int startPosition: 20

    // Resolved once, used to expand relative paths from config.json
    readonly property string homeDir: Quickshell.env("HOME")

    implicitHeight: Screen.height
    implicitWidth: Screen.width
    color: "transparent"
    aboveWindows: true
    exclusionMode: "Ignore"
    exclusiveZone: 1
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Background click dismisses, wheel anywhere navigates
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: Qt.quit()
        onWheel: function(wheel) {
            list.handleWheel(wheel)
        }
    }

    Component.onCompleted:
        Quickshell.execDetached([
            "bash",
            Quickshell.shellPath("cache.sh"),
            Quickshell.shellDir
        ])

    FileView {
        path: Quickshell.shellPath("config.json")
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: configs

            property string wallpaper_path
            property string cache_path
            property int number_of_pictures
            property string border_color
        }
    }

    FolderListModel {
        id: folderModel

        folder: "file://" + main.homeDir + "/" + configs.wallpaper_path
        showDirs: false
        nameFilters: ["*.png", "*.jpg"]
        sortField: FolderListModel.Name
    }

    ListView {
        id: list

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 500
        focus: true
        model: folderModel
        orientation: ListView.Horizontal
        spacing: main.baseSpacing
        clip: false
        cacheBuffer: 400
        boundsBehavior: Flickable.StopAtBounds

        property int selectedIndex: main.startPosition
        property real tileWidth: width / configs.number_of_pictures - 10
        property real viewportCenterX: width / 2
        property bool ready: false

        // Extend the scrollable area on both ends so the first/last
        // wallpaper can be centered in the viewport.
        leftMargin: Math.max(0, viewportCenterX - tileWidth / 2)
        rightMargin: leftMargin

        onCountChanged: {
            if (!ready && count > 0) {
                selectedIndex = clampIndex(main.startPosition)
                ensureVisibleAnimated(selectedIndex)
                ready = true
            }
        }

        property real wheelAccumulator: 0
        property real lastWheelTime: 0
        property real lastStepTime: 0

        function clampIndex(i) {
            return Math.max(0, Math.min(i, count - 1))
        }

        function activateCurrent() {
            Quickshell.execDetached([
                "bash",
                Quickshell.shellPath("commands.sh"),
                folderModel.get(selectedIndex, "filePath")
            ])

            Qt.quit()
        }

        function ensureVisibleAnimated(i) {
            const step = tileWidth + spacing
            const itemStart = i * step

            // Always center the selected tile.
            contentX = itemStart + tileWidth / 2 - viewportCenterX
        }

        function moveSelection(delta) {
            selectedIndex = clampIndex(selectedIndex + delta)
            ensureVisibleAnimated(selectedIndex)
        }

        function handleWheel(wheel) {
            const now = Date.now()
            if (now - lastWheelTime > 250) {
                wheelAccumulator = 0
            }
            lastWheelTime = now

            // Prevent runaway event flooding on sensitive touchpads/free-spinning wheels
            if (now - lastStepTime < 75) {
                wheel.accepted = true
                return
            }

            const raw = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : -wheel.angleDelta.x
            wheelAccumulator += raw

            const threshold = 60
            if (wheelAccumulator <= -threshold) {
                moveSelection(1)
                wheelAccumulator = 0
                lastStepTime = now
            } else if (wheelAccumulator >= threshold) {
                moveSelection(-1)
                wheelAccumulator = 0
                lastStepTime = now
            }
            wheel.accepted = true
        }

        Behavior on contentX {
            enabled: list.ready

            NumberAnimation {
                duration: main.animDuration
                easing.type: Easing.OutCubic
            }
        }

        delegate: Item {
            id: delegateItem

            height: 500
            property bool active: index === list.selectedIndex

            // Base slot width, independent of this item's own width.
            readonly property real baseWidth: list.tileWidth

            // Dock-style magnification based on on-screen position.
            property real scaleFactor: {
                const centerX = x - list.contentX + baseWidth / 2
                const frac = Math.min(
                    1,
                    Math.abs(centerX - list.viewportCenterX) / list.viewportCenterX
                )

                const t = 1 - frac * frac * (3 - 2 * frac)

                return main.edgeScale +
                       (main.zoomScale - main.edgeScale) * t
            }

            width: baseWidth
            z: delegateItem.active ? 100 : Math.round(delegateItem.scaleFactor * 100)

            Item {
                id: content

                anchors.centerIn: parent
                width: delegateItem.baseWidth
                height: delegateItem.height
                scale: delegateItem.scaleFactor

                Text {
                    id: alt

                    text: ""
                    color: configs.border_color
                    anchors.centerIn: parent
                    font.pixelSize: 16

                    transform: Shear {
                        xFactor: main.skewFactor
                    }
                }

                Image {
                    id: img

                    anchors.fill: parent
                    opacity: delegateItem.active ? 1.0 : 0.75
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true

                    source: "file://" +
                            main.homeDir + "/" +
                            configs.cache_path +
                            fileName

                    // Decode once at max zoomed size.
                    sourceSize.width:
                        delegateItem.baseWidth * main.zoomScale

                    sourceSize.height:
                        delegateItem.height

                    transform: Shear {
                        xFactor: main.skewFactor
                    }

                    Timer {
                        id: retryTimer

                        interval: 1000
                        repeat: false

                        onTriggered: {
                            const s = img.source
                            img.source = ""
                            img.source = s
                        }
                    }

                    onStatusChanged: {
                        if (status === Image.Error) {
                            alt.text = "Caching"
                            retryTimer.start()
                        }
                    }
                }

                Rectangle {
                    z: 10
                    anchors.fill: parent
                    visible: delegateItem.active
                    color: "transparent"
                    border.width: 3
                    border.color: configs.border_color

                    transform: Shear {
                        xFactor: main.skewFactor
                    }
                }
            }

            MouseArea {
                anchors.fill: parent

                onClicked: {
                    if (list.selectedIndex === index) {
                        list.activateCurrent()
                    } else {
                        list.selectedIndex = index
                        list.ensureVisibleAnimated(index)
                    }
                }

                onWheel: function(wheel) {
                    list.handleWheel(wheel)
                }
            }
        }

        Keys.onPressed: function(event) {
            switch (event.key) {
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                activateCurrent()
                break
            case Qt.Key_Left:
            case Qt.Key_H:
                moveSelection(-1)
                break
            case Qt.Key_Right:
            case Qt.Key_L:
                moveSelection(1)
                break
            case Qt.Key_Up:
            case Qt.Key_PageUp:
                moveSelection(-5)
                break
            case Qt.Key_Down:
            case Qt.Key_PageDown:
                moveSelection(5)
                break
            case Qt.Key_Escape:
            case Qt.Key_Q:
                Qt.quit()
                break
            default:
                return
            }
            event.accepted = true
        }
    }
}
