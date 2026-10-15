import QtQuick
import Quickshell
import Quickshell.Io
import "."
import "WindowRegistry.js" as LayoutMath 

Item {
    id: root
    visible: false

    property real currentWidth: (Screen.width && Screen.width > 0) ? Screen.width : 1920.0
    property real currentHeight: (Screen.height && Screen.height > 0) ? Screen.height : 1080.0
    property real uiScale: GlobalSettingsWatcher.uiScale
    property real dpiScale: GlobalSettingsWatcher.dpiScale

    property real rawBaseScale: {
        let scrW = (Screen.width && Screen.width > 0) ? Screen.width : 1920.0;
        let scrH = (Screen.height && Screen.height > 0) ? Screen.height : 1080.0;
        let w = (currentWidth && !isNaN(currentWidth) && currentWidth > 0) ? currentWidth : scrW;
        let h = (currentHeight && !isNaN(currentHeight) && currentHeight > 0) ? currentHeight : scrH;
        if (h < scrH * 0.7) h = scrH;
        if (w < scrW * 0.7) w = scrW;
        return LayoutMath.getScale(w, h, uiScale, dpiScale);
    }

    property real baseScale: rawBaseScale
    Behavior on baseScale { NumberAnimation { duration: 150 } }
    
    function s(val) { 
        return LayoutMath.s(val, baseScale); 
    }
}
