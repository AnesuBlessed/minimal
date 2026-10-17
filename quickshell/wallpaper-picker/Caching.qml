import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    readonly property string home: Quickshell.env("HOME")
    readonly property string xdgRuntimeDir: Quickshell.env("XDG_RUNTIME_DIR")
    readonly property string minimalRoot: Quickshell.env("MINIMAL_ROOT") || (home + "/Projects/minimal")
    readonly property string minimalCache: Quickshell.env("MINIMAL_CACHE") || (home + "/.cache/minimal")
    readonly property string minimalState: Quickshell.env("MINIMAL_STATE") || (home + "/.local/state/minimal")
    readonly property string minimalRuntime: Quickshell.env("MINIMAL_RUNTIME") || (xdgRuntimeDir !== "" ? (xdgRuntimeDir + "/minimal") : (minimalCache + "/run"))

    // Persistent data on disk
    readonly property string cacheDir: minimalCache + "/wallpaper-picker"
    readonly property string stateDir: minimalState + "/wallpaper-picker"

    // Ephemeral data in RAM / runtime
    readonly property string runDir: minimalRuntime + "/wallpaper-picker"
    readonly property string logDir: runDir + "/logs"

    Process {
        id: dirSetup
        running: true
        command: ["bash", "-c", 'umask 077; mkdir -p -- "$@"', "minimal-dirs", root.cacheDir, root.stateDir, root.runDir, root.logDir]
    }

    property var _ensured: ({})

    function _ensureOnce(path) {
        if (_ensured[path]) return;
        _ensured[path] = true;
        Quickshell.execDetached(["mkdir", "-p", path]);
    }

    function getCacheDir(widgetName) {
        let envPath = Quickshell.env("QS_CACHE_" + widgetName.toUpperCase());
        if (envPath) { _ensureOnce(envPath); return envPath; }
        let p = cacheDir;
        _ensureOnce(p);
        return p;
    }

    function getStateDir(widgetName) {
        let envPath = Quickshell.env("QS_STATE_" + widgetName.toUpperCase());
        if (envPath) { _ensureOnce(envPath); return envPath; }
        let p = stateDir;
        _ensureOnce(p);
        return p;
    }

    function getRunDir(widgetName) {
        let envPath = Quickshell.env("QS_RUN_" + widgetName.toUpperCase());
        if (envPath) { _ensureOnce(envPath); return envPath; }
        let p = runDir;
        _ensureOnce(p);
        return p;
    }

    function getLogDir(widgetName) {
        let envPath = Quickshell.env("QS_LOG_" + widgetName.toUpperCase());
        if (envPath) { _ensureOnce(envPath); return envPath; }
        let p = logDir;
        _ensureOnce(p);
        return p;
    }
}
