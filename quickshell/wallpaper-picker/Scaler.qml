import QtQuick
import Quickshell
import "."
import "WindowRegistry.js" as LayoutMath

Item {
    id: root
    visible: false

    property real currentWidth: Screen.width || 1920.0
    property real currentHeight: Screen.height || 1080.0
    property real uiScale: 1.0
    property real dpiScale: 1.0
    property real baseScale: 1.0

    function s(val) {
        return Math.round(val);
    }
}
