pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property color base: "#1e1e2e"
    property color mantle: "#181825"
    property color crust: "#11111b"
    property color text: "#cdd6f4"
    property color subtext0: "#a6adc8"
    property color subtext1: "#bac2de"
    property color surface0: "#313244"
    property color surface1: "#45475a"
    property color surface2: "#585b70"
    property color overlay0: "#6c7086"
    property color overlay1: "#7f849c"
    property color overlay2: "#9399b2"
    property color blue: "#89b4fa"
    property color sapphire: "#74c7ec"
    property color peach: "#fab387"
    property color green: "#a6e3a1"
    property color red: "#f38ba8"
    property color mauve: "#cba6f7"
    property color pink: "#f5c2e7"
    property color yellow: "#f9e2af"
    property color maroon: "#eba0ac"
    property color teal: "#94e2d5"

    readonly property string home: Quickshell.env("HOME")
    readonly property string minimalCache: Quickshell.env("MINIMAL_CACHE") || (home + "/.cache/minimal")
    readonly property string colorsFile: minimalCache + "/qs_colors.json"

    function applyColors(content) {
        try {
            let parsed = JSON.parse(content);
            if (parsed.base) root.base = parsed.base;
            if (parsed.mantle) root.mantle = parsed.mantle;
            if (parsed.crust) root.crust = parsed.crust;
            if (parsed.text) root.text = parsed.text;
            if (parsed.subtext0) root.subtext0 = parsed.subtext0;
            if (parsed.subtext1) root.subtext1 = parsed.subtext1;
            if (parsed.surface0) root.surface0 = parsed.surface0;
            if (parsed.surface1) root.surface1 = parsed.surface1;
            if (parsed.surface2) root.surface2 = parsed.surface2;
            if (parsed.overlay0) root.overlay0 = parsed.overlay0;
            if (parsed.overlay1) root.overlay1 = parsed.overlay1;
            if (parsed.overlay2) root.overlay2 = parsed.overlay2;
            if (parsed.blue) root.blue = parsed.blue;
            if (parsed.sapphire) root.sapphire = parsed.sapphire;
            if (parsed.peach) root.peach = parsed.peach;
            if (parsed.green) root.green = parsed.green;
            if (parsed.red) root.red = parsed.red;
            if (parsed.mauve) root.mauve = parsed.mauve;
            if (parsed.pink) root.pink = parsed.pink;
            if (parsed.yellow) root.yellow = parsed.yellow;
            if (parsed.maroon) root.maroon = parsed.maroon;
            if (parsed.teal) root.teal = parsed.teal;
        } catch (e) {
            console.warn("GlobalTheme: could not parse qs_colors.json:", e);
        }
    }

    Process {
        id: themeReader
        command: ["bash", "-c", "cat " + root.colorsFile + " 2>/dev/null || echo '{}'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text && this.text.trim().length > 0) {
                    root.applyColors(this.text.trim());
                }
            }
        }
    }

    Process {
        id: themeWatcher
        command: ["bash", "-c", "while [ ! -f " + root.colorsFile + " ]; do sleep 2; done; inotifywait -qq -e close_write,modify " + root.colorsFile + " 2>/dev/null || sleep 2"]
        running: true
        onExited: {
            themeReader.running = false;
            themeReader.running = true;
            running = false;
            running = true;
        }
    }
}
