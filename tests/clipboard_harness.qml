import QtQuick
import Quickshell

ShellRoot {
    ClipboardManager { id: manager; width: 800; height: 700 }
    Timer {
        interval: 100
        running: true
        repeat: true
        property int stage: 0
        property int ticks: 0
        onTriggered: {
            ticks++;
            if (ticks > 100) {
                console.log("REGRESSION_FAIL timeout", stage, manager.allClips.length);
                Qt.quit();
                return;
            }
            if (manager.isLoading) return;
            if (stage === 0) {
                if (manager.allClips.length < 60) {
                    manager.loadMore();
                    manager.loadMore();
                    return;
                }
                const ids = manager.allClips.map(item => String(item.id));
                if (ids.length !== 60 || new Set(ids).size !== 60 || ids[59] !== "1") {
                    console.log("REGRESSION_FAIL pagination", JSON.stringify(ids));
                    Qt.quit();
                    return;
                }
                stage = 1;
                manager.mutateClipboard("delete", "60");
            } else if (stage === 1 && manager.allClips.length > 0 && String(manager.allClips[0].id) === "59") {
                stage = 2;
                manager.mutateClipboard("wipe", "");
            } else if (stage === 2 && manager.allClips.length === 0) {
                console.log("REGRESSION_PASS pagination delete wipe");
                Qt.quit();
            }
        }
    }
}
