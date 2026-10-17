pragma Singleton
import QtQuick

QtObject {
    id: root
    property real uiScale: 1.0
    property real dpiScale: 1.0
    readonly property var rawSettings: ({})
    property string currentActiveWidget: "wallpaper"
    signal settingsChanged()
}
