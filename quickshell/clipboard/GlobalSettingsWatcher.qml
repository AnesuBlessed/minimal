pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    readonly property string home: Quickshell.env("HOME")
    readonly property string minimalRoot: Quickshell.env("MINIMAL_ROOT") || (home + "/Projects/minimal")
    readonly property string minimalConfig: Quickshell.env("MINIMAL_CONFIG") || (home + "/.config")
    readonly property string settingsFile: minimalConfig + "/minimal/settings.json"

    property real uiScale: 1.0
    property real dpiScale: 1.0
    readonly property var rawSettings: _raw

    property var _raw: ({})
    property string currentActiveWidget: "wallpaper"
    signal settingsChanged()

    function readSettings(content) {
        try {
            let str = content || (scaleCollector.text ? scaleCollector.text.trim() : "");
            if (str && str.length > 0 && str !== "{}") {
                _raw = JSON.parse(str);
                if (_raw.uiScale !== undefined && !isNaN(_raw.uiScale)) {
                    root.uiScale = _raw.uiScale;
                }
                settingsChanged();
            }
        } catch (e) {
            console.warn("GlobalSettingsWatcher: could not parse settings.json:", e);
        }
    }

    Process {
        id: scaleReader
        command: ["bash", "-c", "cat " + root.settingsFile + " 2>/dev/null || echo '{}'"]
        running: true
        stdout: StdioCollector {
            id: scaleCollector
            onStreamFinished: {
                root.readSettings(this.text);
            }
        }
    }

    Process {
        id: scaleWatcher
        command: ["bash", "-c", "while [ ! -f " + root.settingsFile + " ]; do sleep 2; done; inotifywait -qq -e modify,close_write,move_self " + root.settingsFile + " 2>/dev/null || sleep 2"]
        running: true
        onExited: {
            scaleReader.running = false;
            scaleReader.running = true;
            running = false;
            running = true;
        }
    }

    Process {
        id: dpiReader
        running: true
        command: ["bash", "-c",
            "hyprctl monitors -j 2>/dev/null " +
            "| jq -r '[.[].scale] | max // 1' 2>/dev/null || echo 1"]
        stdout: StdioCollector {
            onStreamFinished: {
                let v = parseFloat(this.text ? this.text.trim() : "");
                if (!isNaN(v) && v > 0) {
                    root.dpiScale = Math.min(Math.max(v, 0.5), 3.0);
                }
            }
        }
    }
}
