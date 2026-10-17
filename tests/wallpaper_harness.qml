import QtQuick
import Quickshell

ShellRoot {
    WallpaperPicker { id: picker; width: 800; height: 700 }
    Timer {
        interval: 100
        running: true
        repeat: true
        property int ticks: 0
        property bool started: false
        onTriggered: {
            ticks++;
            if (ticks > 50) {
                console.log("REGRESSION_FAIL download stuck");
                Qt.quit();
                return;
            }
            if (!started) {
                picker.currentFilter = "Search";
                picker.hasSearched = true;
                picker.applyWallpaper("fixture.jpg", false);
                started = true;
                if (!picker.isDownloadingWallpaper) {
                    console.log("REGRESSION_FAIL download did not start");
                    Qt.quit();
                }
            } else if (!picker.isDownloadingWallpaper) {
                console.log("REGRESSION_PASS failed download clears state");
                Qt.quit();
            }
        }
    }
}
