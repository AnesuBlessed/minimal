import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtCore
import Qt.labs.folderlistmodel
import QtMultimedia
import Quickshell
import Quickshell.Io
import "."

Item {
    id: window
    width: Screen.width

    Caching { id: paths }

    Scaler {
        id: scaler
        currentWidth: Screen.width
        currentHeight: Screen.height
    }

    function s(val) {
        return scaler.s(val);
    }

    MatugenColors { id: _theme }

    readonly property string minimalRoot: Quickshell.env("MINIMAL_ROOT") || (Quickshell.env("HOME") + "/Projects/minimal")
    readonly property string thumbDir: "file://" + paths.getCacheDir("wallpaper_picker") + "/thumbs"
    readonly property string searchDir: "file://" + paths.getCacheDir("wallpaper_picker") + "/search_thumbs"
    readonly property string markerDir: "file://" + paths.getCacheDir("wallpaper_picker") + "/colors_markers"
    readonly property string srcDir: {
        const dir = Quickshell.env("MINIMAL_WALLPAPERS") || Quickshell.env("WALLPAPER_DIR")
        return (dir && dir !== "")
        ? dir
        : (minimalRoot + "/wallpapers")
    }

    property string targetWallName: Quickshell.env("MINIMAL_CURRENT_WALLPAPER") || ""
    property bool initialFocusSet: false
    property int visibleItemCount: -1
    property int scrollAccum: 0
    property real scrollThreshold: window.s(300)

    property string currentFilter: "All"
    property string _lastFilter: "All"
    property string searchQuery: ""
    property bool isOnlineSearch: false
    property bool isSearchPaused: false
    property bool hasSearched: false
    property var colorMap: ({})
    property int cacheVersion: 0

    property bool isDownloadingWallpaper: false
    property string currentDownloadName: ""

    Process {
        id: downloadProcess
        onExited: (exitCode, exitStatus) => {
            const wasDownload = window.currentDownloadName !== "";
            window.isDownloadingWallpaper = false;
            window.currentDownloadName = "";
            if (exitCode !== 0)
                Quickshell.execDetached(["notify-send", wasDownload ? "Wallpaper download failed" : "Wallpaper apply failed", "Please try another image."]);
        }
    }

    property bool isApplying: false
    property bool isMonitorSelectorOpen: false

    // Separate flag so add-animations fire on new arrivals
    // even before the first focus snap has happened
    property bool allowAddAnimation: false

    Timer {
        id: applyUnlockTimer
        interval: 120
        onTriggered: window.isApplying = false
    }

    property bool isStartup: localFolderModel.status === FolderListModel.Loading
    property bool isReady: visible && localFolderModel.status === FolderListModel.Ready
    property bool isSearchActive: window.currentFilter === "Search" && window.hasSearched && searchFolderModel.status === FolderListModel.Loading

    property string lastSearchName: ""
    property bool isModelChanging: false
    property bool searchIndexRestored: false

    property bool isScrollingBlocked: window.currentFilter === "Search" && window.hasSearched && window.isSearchActive && !window.isSearchPaused
    property bool jumpToLastOnFilterChange: false

    readonly property var filterData: [
        { name: "All", hex: "", label: "All" },
        { name: "Video", hex: "", label: "Vid" },
        { name: "Red", hex: "#FF4500", label: "" },
        { name: "Orange", hex: "#FFA500", label: "" },
        { name: "Yellow", hex: "#FFD700", label: "" },
        { name: "Green", hex: "#32CD32", label: "" },
        { name: "Blue", hex: "#1E90FF", label: "" },
        { name: "Purple", hex: "#8A2BE2", label: "" },
        { name: "Pink", hex: "#FF69B4", label: "" },
        { name: "Monochrome", hex: "#A9A9A9", label: "" },
        { name: "Search", hex: "", label: "Search" }
    ]

    ListModel { id: monitorModel }

    Process {
        id: monitorProc
        command: ["hyprctl", "monitors", "-j"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                let response = this.text;
                if (response && response.trim().length > 0) {
                    try {
                        var monitors = JSON.parse(response);
                        monitorModel.clear();
                        for (var i = 0; i < monitors.length; i++) {
                            monitorModel.append({ "name": monitors[i].name, "selected": true });
                        }
                    } catch(e) {
                        console.warn("WallpaperPicker: failed to parse monitors JSON from hyprctl:", e);
                    }
                }
            }
        }
    }

    function loadMonitors() {
        monitorProc.running = true;
    }

    function getMonitorOutputs() {
        if (monitorModel.count <= 1) return "all";

        let selected = [];
        for (let i = 0; i < monitorModel.count; i++) {
            if (monitorModel.get(i).selected) {
                selected.push(monitorModel.get(i).name);
            }
        }

        if (selected.length === 0) return "none";
        if (selected.length === monitorModel.count) return "all";

        return selected.join(",");
    }

    function applyWallpaper(safeFileName, isVideo) {
        if (!safeFileName || window.isApplying || window.isDownloadingWallpaper) return;

        let outputs = window.getMonitorOutputs();
        if (outputs === "none") return;

        window.isApplying = true;
        applyUnlockTimer.restart();

        window.targetWallName = safeFileName;
        let cleanName = window.getCleanName(safeFileName);

        if (window.currentFilter === "Search" && window.hasSearched) {
            window.isDownloadingWallpaper = true;
            window.currentDownloadName = safeFileName;
            downloadProcess.command = [Quickshell.shellDir + "/apply-search.sh", safeFileName, outputs];
            downloadProcess.running = true;
            return;
        }
        const originalFile = window.srcDir + "/" + cleanName;
        const thumbFile = paths.getCacheDir("wallpaper_picker") + "/thumbs/" + safeFileName;

        window.isDownloadingWallpaper = true;
        window.currentDownloadName = "";
        downloadProcess.command = isVideo
            ? [window.minimalRoot + "/scripts/wallpaper-video.sh", originalFile, outputs, thumbFile]
            : [window.minimalRoot + "/scripts/wallpaper.sh", originalFile, outputs];
        downloadProcess.running = true;
    }

    Settings {
        id: searchState
        category: "QS_WallpaperPicker"
        location: "file://" + paths.minimalState + "/wallpaper-search.ini"
        property string query: ""
        property bool searched: false
        property string lastName: ""
    }

    onIsSearchPausedChanged: {
        Quickshell.execDetached([Quickshell.shellDir + "/search-control.sh", isSearchPaused ? "pause" : "run"]);
    }

    onVisibleChanged: {
        if (!visible) {
            window.initialFocusSet = false;
            window.allowAddAnimation = false;
            window.searchIndexRestored = false;
            window.isApplying = false;
            window.isMonitorSelectorOpen = false;

            if (window.hasSearched) {
                window.isSearchPaused = true;
            }
        } else {
            window.isFilterAnimating = true;
            filterAnimationTimer.restart();

            if (window.currentFilter !== "Search") {
                window.applyFilters(true);
            } else if (window.hasSearched) {
                window.searchIndexRestored = false;
                window.isSearchPaused = true;
                window.trySearchFocus();
                window.syncSearchModel();
            }
        }
    }

    property bool isLoading: localFolderModel.status === FolderListModel.Loading ||
                             (window.currentFilter === "Search" && searchFolderModel.status === FolderListModel.Loading)

    property bool showSpinner: window.isDownloadingWallpaper ||
                               (window.currentFilter === "Search" && window.hasSearched && !window.isSearchPaused) ||
                               (window.currentFilter !== "Search" && window.isLoading)

    property string currentNotification: {
        if (window.isDownloadingWallpaper) return window.currentDownloadName !== "" ? "Downloading wallpaper..." : "Applying wallpaper...";

        if (window.currentFilter === "Search") {
            if (!window.hasSearched) return "Type something to search...";
            if (window.isSearchPaused) return "Search Paused";
            if (window.visibleItemCount === 0) return "Searching DDG (FHD+)...";
            return "Generating thumbnails...";
        }

        if (isLoading) return "Generating thumbnails...";
        if (window.visibleItemCount === 0) return "No wallpapers found";

        if (window.currentFilter === "All") return "";
        if (window.currentFilter === "Video") return "Videos";

        return window.currentFilter;
    }

    property bool showNotification: !window.isStartup && currentNotification !== ""

    function getCleanName(name) {
        if (!name) return "";
        let clean = String(name);
        return clean.startsWith("000_") ? clean.substring(4) : clean;
    }

    function executeFocusRestore(targetIndex, isSearchRestore, requirePositioning) {
        let targetModel = window.getModelForFilter(window.currentFilter);

        if (targetIndex !== -1 && targetIndex < targetModel.count) {
            window.isModelChanging = true;

            if (requirePositioning) {
                view.forceLayout();
                view.positionViewAtIndex(targetIndex, ListView.Center);
            }

            view.currentIndex = targetIndex;

            if (isSearchRestore) {
                window.searchIndexRestored = true;
            }

            window.isModelChanging = false;
            window.initialFocusSet = true;

            // Allow add-animations for future incremental arrivals
            // Use a short delay so the initial snap itself isn't animated
            allowAddAnimationTimer.restart();
        } else if (isSearchRestore) {
            window.searchIndexRestored = true;
        }
    }

    Timer {
        id: allowAddAnimationTimer
        interval: 120
        onTriggered: window.allowAddAnimation = true
    }

    function tryFocus() {
        if (initialFocusSet) return;

        if (localProxyModel.count > 0) {
            let foundIndex = -1;
            let cleanTarget = window.getCleanName(targetWallName);

            if (cleanTarget !== "") {
                for (let i = 0; i < localProxyModel.count; i++) {
                    let fname = localProxyModel.get(i).fileName || "";
                    if (window.getCleanName(fname) === cleanTarget) {
                        foundIndex = i;
                        break;
                    }
                }
            }

            let finalIndex = foundIndex !== -1 ? foundIndex : 0;
            window.executeFocusRestore(finalIndex, false, true);
        }
    }

    function trySearchFocus() {
        if (window.searchIndexRestored || searchProxyModel.count === 0) return;

        if (window.lastSearchName === "") {
             window.searchIndexRestored = true;
             return;
        }

        for (let i = 0; i < searchProxyModel.count; i++) {
            let fname = searchProxyModel.get(i).fileName || "";
            if (fname === window.lastSearchName) {
                window.executeFocusRestore(i, true, true);
                return;
            }
        }

        if (searchFolderModel.status === FolderListModel.Ready && searchProxyModel.count === searchFolderModel.count) {
             window.searchIndexRestored = true;
        }
    }

    function getModelForFilter(filter) {
        return filter === "Search" ? searchProxyModel : localProxyModel;
    }

    function updateVisibleCount() {
        let targetModel = window.getModelForFilter(window.currentFilter);

        if (!targetModel || targetModel.count === 0) {
            window.visibleItemCount = 0;
            return;
        }
        let count = 0;
        for (let i = 0; i < targetModel.count; i++) {
            let fname = targetModel.get(i).fileName || "";
            let isVid = fname.startsWith("000_");
            if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                count++;
            }
        }
        window.visibleItemCount = count;
    }

    function triggerOnlineSearch() {
        if (searchInput.text.trim() === "") return;

        window.isModelChanging = true;
        searchProxyModel.clear();
        window.lastSearchName = "";
        searchState.lastName = "";

        if (window.currentFilter === "Search") {
            view.currentIndex = 0;
            view.positionViewAtIndex(0, ListView.Center);
        }
        window.isModelChanging = false;

        window.searchIndexRestored = true;
        window.isOnlineSearch = true;
        window.hasSearched = true;

        window.visibleItemCount = 0;

        searchState.searched = true;
        searchState.query = searchInput.text.trim();

        window.isSearchPaused = false;
        window.searchQuery = searchInput.text.trim();

        const script = decodeURIComponent(Qt.resolvedUrl("start-search.sh").toString().replace(/^file:\/\//, ""));
        Quickshell.execDetached(["bash", script, window.searchQuery]);

        searchInput.focus = false;
        view.forceActiveFocus();
    }

    readonly property real itemWidth: window.s(400)
    readonly property real itemHeight: window.s(420)
    readonly property real borderWidth: window.s(3)
    readonly property real spacing: window.s(10)
    readonly property real skewFactor: -0.35

    Timer {
        id: scrollThrottle
        interval: 80
    }

    property bool isFilterAnimating: false
    Timer {
        id: filterAnimationTimer
        interval: 120
        onTriggered: window.isFilterAnimating = false
    }

    property bool isItemAnimating: false
    Timer {
        id: itemAnimationTimer
        interval: 120
        onTriggered: window.isItemAnimating = false
    }

    function getHexBucket(hexStr) {
        if (!hexStr) return "Monochrome";

        hexStr = String(hexStr).trim().replace(/#/g, '');
        if (hexStr.length > 6) hexStr = hexStr.substring(0, 6);
        if (hexStr.length !== 6) return "Monochrome";

        let r = parseInt(hexStr.substring(0,2), 16) / 255;
        let g = parseInt(hexStr.substring(2,4), 16) / 255;
        let b = parseInt(hexStr.substring(4,6), 16) / 255;

        if (isNaN(r) || isNaN(g) || isNaN(b)) return "Monochrome";

        let max = Math.max(r, g, b), min = Math.min(r, g, b);
        let d = max - min;

        let h = 0;
        let s = max === 0 ? 0 : d / max;
        let v = max;

        if (max !== min) {
            if (max === r) {
                h = (g - b) / d + (g < b ? 6 : 0);
            } else if (max === g) {
                h = (b - r) / d + 2;
            } else {
                h = (r - g) / d + 4;
            }
            h /= 6;
        }
        h = h * 360;

        if (s < 0.05 || v < 0.08) return "Monochrome";

        if (h >= 345 || h < 15) return "Red";
        if (h >= 15 && h < 45) return "Orange";
        if (h >= 45 && h < 75) return "Yellow";
        if (h >= 75 && h < 165) return "Green";
        if (h >= 165 && h < 260) return "Blue";
        if (h >= 260 && h < 315) return "Purple";
        if (h >= 315 && h < 345) return "Pink";

        return "Monochrome";
    }

    function checkItemMatchesFilter(fileName, isVid, cv, filter) {
        if (filter === "Search") return true;

        if (filter === "All") return true;
        if (filter === "Video") return isVid;

        let hexColor = window.colorMap[String(fileName)];
        if (!hexColor) return filter === "Monochrome";

        return window.getHexBucket(hexColor) === filter;
    }

    FolderListModel {
        id: markerModel
        folder: window.markerDir
        showDirs: false
        nameFilters: ["*_HEX_*"]

        onCountChanged: window.processMarkers()
        onStatusChanged: {
            if (status === FolderListModel.Ready) window.processMarkers()
        }
    }

    function processMarkers() {
        let newMap = {};
        for (let i = 0; i < markerModel.count; i++) {
            let markerName = markerModel.get(i, "fileName") || "";
            if (!markerName) continue;

            let splitIdx = markerName.lastIndexOf("_HEX_");
            if (splitIdx !== -1) {
                let fName = markerName.substring(0, splitIdx);
                let hexCode = markerName.substring(splitIdx + 5);
                newMap[fName] = "#" + hexCode;
            }
        }
        window.colorMap = newMap;
        window.cacheVersion++;
        window.updateVisibleCount();
    }

    Process {
        id: thumbnailProcess
        command: ["bash", Quickshell.shellDir + "/generate_thumbs.sh"]
    }
    function triggerThumbnailGeneration() {
        if (!thumbnailProcess.running) thumbnailProcess.running = true;
    }

    function stepToNextValidIndex(direction) {
        let targetModel = window.getModelForFilter(window.currentFilter);
        if (!targetModel || targetModel.count === 0) return;

        let start = view.currentIndex;
        let found = -1;

        if (direction === 1) {
            for (let i = start + 1; i < targetModel.count; i++) {
                let fname = targetModel.get(i).fileName || "";
                let isVid = fname.startsWith("000_");
                if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                    found = i; break;
                }
            }
        } else {
            for (let i = start - 1; i >= 0; i--) {
                let fname = targetModel.get(i).fileName || "";
                let isVid = fname.startsWith("000_");
                if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                    found = i; break;
                }
            }
        }

        if (found !== -1) {
            view.currentIndex = found;
            return;
        }

        let filterOrder = ["All", "Video", "Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink", "Monochrome"];
        let currentFilterIdx = filterOrder.indexOf(window.currentFilter);

        if (currentFilterIdx === -1) {
            let current = start;
            for (let i = 0; i < targetModel.count; i++) {
                current = (current + direction + targetModel.count) % targetModel.count;
                let fname = targetModel.get(current).fileName || "";
                let isVid = fname.startsWith("000_");

                if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                    view.currentIndex = current;
                    return;
                }
            }
            return;
        }

        let nextFilterIdx = currentFilterIdx + direction;

        if (nextFilterIdx >= 0 && nextFilterIdx < filterOrder.length) {
            window.jumpToLastOnFilterChange = (direction === -1);
            window.currentFilter = filterOrder[nextFilterIdx];
        }
    }

    function cycleFilter(direction) {
        let currentIdx = -1;
        for (let i = 0; i < window.filterData.length; i++) {
            if (window.filterData[i].name === window.currentFilter) {
                currentIdx = i;
                break;
            }
        }

        if (currentIdx !== -1) {
            let nextIdx = (currentIdx + direction + window.filterData.length) % window.filterData.length;
            window.currentFilter = window.filterData[nextIdx].name;
        }
    }

    function applyFilters(forceSnap) {
        let targetModel = window.getModelForFilter(window.currentFilter);

        if (!targetModel || targetModel.count === 0) {
            window.updateVisibleCount();
            return;
        }

        if (window.currentFilter === "Search") {
            window.updateVisibleCount();
            return;
        }

        let firstValidIndex = -1;
        let lastValidIndex = -1;
        let cleanTarget = window.getCleanName(window.targetWallName);
        let targetIndex = -1;

        for (let i = 0; i < targetModel.count; i++) {
            let fname = targetModel.get(i).fileName || "";
            let isVid = fname.startsWith("000_");

            if (checkItemMatchesFilter(fname, isVid, window.cacheVersion, window.currentFilter)) {
                if (firstValidIndex === -1) {
                    firstValidIndex = i;
                }
                lastValidIndex = i;

                if (cleanTarget !== "" && window.getCleanName(fname) === cleanTarget) {
                    targetIndex = i;
                }
            }
        }

        let indexToFocus = -1;

        if (targetIndex !== -1) {
             indexToFocus = targetIndex;
        } else if (window.jumpToLastOnFilterChange && lastValidIndex !== -1) {
            indexToFocus = lastValidIndex;
        } else if (firstValidIndex !== -1) {
            indexToFocus = firstValidIndex;
        }

        window.jumpToLastOnFilterChange = false;

        if (indexToFocus !== -1) {
            window.executeFocusRestore(indexToFocus, false, forceSnap === true);
        }

        window.updateVisibleCount();
    }

    onCurrentFilterChanged: {
        window.isFilterAnimating = true;
        filterAnimationTimer.restart();
        window.isModelChanging = true;
        let returningFromSearch = (window._lastFilter === "Search" && window.currentFilter !== "Search");
        window._lastFilter = window.currentFilter;

        if (returningFromSearch) {
             window.searchIndexRestored = false;
        }

        Qt.callLater(() => {
            view.forceActiveFocus();

            if (window.currentFilter === "Search") {
                if (window.hasSearched) {
                    window.searchIndexRestored = false;
                    window.trySearchFocus();
                }
            } else {
                window.applyFilters(returningFromSearch);
            }
            window.isModelChanging = false;
        });
    }

    Shortcut {
        sequence: "Left"
        enabled: !searchInput.activeFocus && !window.isScrollingBlocked && !window.isApplying
        onActivated: window.stepToNextValidIndex(-1)
    }
    Shortcut {
        sequence: "Right"
        enabled: !searchInput.activeFocus && !window.isScrollingBlocked && !window.isApplying
        onActivated: window.stepToNextValidIndex(1)
    }
    Shortcut {
        sequence: "H"
        enabled: !searchInput.activeFocus && !window.isScrollingBlocked && !window.isApplying
        onActivated: window.stepToNextValidIndex(-1)
    }
    Shortcut {
        sequence: "L"
        enabled: !searchInput.activeFocus && !window.isScrollingBlocked && !window.isApplying
        onActivated: window.stepToNextValidIndex(1)
    }

    Shortcut {
        sequence: "Return"
        enabled: !searchInput.activeFocus && !window.isScrollingBlocked && !window.isApplying
        onActivated: {
            let targetModel = window.getModelForFilter(window.currentFilter);
            if (view.currentIndex >= 0 && view.currentIndex < targetModel.count) {
                let fname = targetModel.get(view.currentIndex).fileName;
                if (fname) {
                    let isVid = String(fname).startsWith("000_");
                    window.applyWallpaper(String(fname), isVid);
                }
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: !window.isApplying
        onActivated: {
            if (searchInput.activeFocus) {
                searchInput.focus = false;
                view.forceActiveFocus();
            } else if (window.currentFilter === "Search") {
                window.currentFilter = "All";
            } else {
                Qt.quit();
            }
        }
    }
    Shortcut { sequence: "Tab"; enabled: !window.isApplying; onActivated: window.cycleFilter(1) }
    Shortcut { sequence: "Backtab"; enabled: !window.isApplying; onActivated: window.cycleFilter(-1) }

    ListModel { id: localProxyModel }
    ListModel { id: searchProxyModel }

    readonly property var activeModel: window.currentFilter === "Search" ? searchProxyModel : localProxyModel

    FolderListModel {
        id: localFolderModel
        folder: window.thumbDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.mp4", "*.mkv", "*.mov", "*.webm"]
        showDirs: false
        sortField: FolderListModel.Name

        onCountChanged: window.syncLocalModel()
        onStatusChanged: { if (status === FolderListModel.Ready) window.syncLocalModel() }
    }

    property int _localSyncedCount: 0

    function syncLocalModel() {
        let folderCount = localFolderModel.count;

        if (folderCount < window._localSyncedCount) {
            let wasAllowing = window.allowAddAnimation;
            window.allowAddAnimation = false;
            window.isModelChanging = true;

            localProxyModel.clear();
            window._localSyncedCount = 0;

            window.isModelChanging = false;
            window.syncLocalModel();
            if (wasAllowing) allowAddAnimationTimer.restart();
            return;
        }

        if (folderCount > window._localSyncedCount) {
            let batch = [];
            for (let i = window._localSyncedCount; i < folderCount; i++) {
                let fn = localFolderModel.get(i, "fileName");
                let fu = localFolderModel.get(i, "fileUrl");
                if (fn !== undefined) {
                    batch.push({ "fileName": fn, "fileUrl": String(fu) });
                }
            }

            if (batch.length > 0) {
                localProxyModel.append(batch);
            }

            window._localSyncedCount = folderCount;
        }

        if (window.currentFilter !== "Search") window.updateVisibleCount();

        if (!window.initialFocusSet && window.currentFilter !== "Search" && localProxyModel.count > 0) {
            window.tryFocus();
        }
    }

    function syncSearchModel() {
        let startIdx = searchProxyModel.count;
        let endIdx = searchFolderModel.count;

        if (endIdx < startIdx) {
            window.isModelChanging = true;
            searchProxyModel.clear();
            startIdx = 0;
            window.isModelChanging = false;
        }

        let batch = [];
        for (let i = startIdx; i < endIdx; i++) {
            let fn = searchFolderModel.get(i, "fileName");
            let fu = searchFolderModel.get(i, "fileUrl");
            if (fn !== undefined) {
                batch.push({ "fileName": fn, "fileUrl": String(fu) });
            }
        }

        if (batch.length > 0) {
            searchProxyModel.append(batch);
        }

        if (window.currentFilter === "Search") window.updateVisibleCount();

        if (window.currentFilter === "Search" && window.hasSearched) {
            if (!window.searchIndexRestored) {
                window.trySearchFocus();
            }

            if (window.isScrollingBlocked && startIdx === 0 && searchProxyModel.count > 0 && window.lastSearchName === "") {
                view.forceLayout();
                view.currentIndex = 0;
                view.positionViewAtIndex(0, ListView.Center);
            }
        }
    }

    FolderListModel {
        id: searchFolderModel
        folder: window.searchDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.mp4", "*.mkv", "*.mov", "*.webm"]
        showDirs: false
        sortField: FolderListModel.Name

        onFolderChanged: {
            window.isModelChanging = true;
            searchProxyModel.clear()
            window.isModelChanging = false;
        }

        onCountChanged: window.syncSearchModel()
        onStatusChanged: { if (status === FolderListModel.Ready) window.syncSearchModel() }
    }

    ListView {
        id: view
        anchors.fill: parent

        opacity: window.isReady ? 1.0 : 0.0
        anchors.margins: window.isReady ? 0 : window.s(40)

        Behavior on opacity { NumberAnimation { duration: _theme.duration; easing.type: Easing.OutQuart } }
        Behavior on anchors.margins { NumberAnimation { duration: _theme.duration; easing.type: Easing.OutExpo } }

        spacing: 0
        orientation: ListView.Horizontal
        clip: false

        interactive: !window.isScrollingBlocked && !window.isApplying
        cacheBuffer: Math.max(0, Math.min(width, 800))

        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width / 2) - ((window.itemWidth * 1.5 + window.spacing) / 2)
        preferredHighlightEnd: (width / 2) + ((window.itemWidth * 1.5 + window.spacing) / 2)

        highlightMoveDuration: window.initialFocusSet ? 120 : 0
        focus: true

        onCurrentIndexChanged: {
            window.isItemAnimating = true;
            itemAnimationTimer.restart();

            if (view.model !== searchProxyModel || window.currentFilter !== "Search") return;

            if (!window.isModelChanging && window.hasSearched && window.searchIndexRestored) {
                if (currentIndex >= 0 && currentIndex < searchProxyModel.count) {
                    let fname = searchProxyModel.get(currentIndex).fileName;
                    if (fname !== undefined && fname !== "") {
                        window.lastSearchName = String(fname);
                        searchState.lastName = String(fname);
                    }
                }
            }
        }

        add: Transition {
            enabled: window.allowAddAnimation
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: _theme.duration; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.5; to: 1; duration: _theme.duration; easing.type: Easing.OutCubic }
            }
        }
        addDisplaced: Transition {
            enabled: window.allowAddAnimation
            NumberAnimation { property: "x"; duration: _theme.duration; easing.type: Easing.OutCubic }
        }

        header: Item { width: Math.max(0, (view.width / 2) - ((window.itemWidth * 1.5) / 2)) }
        footer: Item { width: Math.max(0, (view.width / 2) - ((window.itemWidth * 1.5) / 2)) }

        model: window.activeModel

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton

            onWheel: (wheel) => {
                if (window.isScrollingBlocked || window.isApplying) {
                    wheel.accepted = true;
                    return;
                }

                if (scrollThrottle.running) {
                   wheel.accepted = true
                   return
                }

                let dx = wheel.angleDelta.x
                let dy = wheel.angleDelta.y
                let delta = Math.abs(dx) > Math.abs(dy) ? dx : dy

                scrollAccum += delta

                if (Math.abs(scrollAccum) >= scrollThreshold) {
                    window.stepToNextValidIndex(scrollAccum > 0 ? -1 : 1)
                    scrollAccum = 0
                    scrollThrottle.start()
                }

                wheel.accepted = true
            }
        }

        delegate: Item {
            id: delegateRoot

            readonly property string safeFileName: fileName !== undefined ? String(fileName) : ""

            readonly property bool isCurrent: ListView.isCurrentItem && !window.isScrollingBlocked
            readonly property bool isFakeSelected: window.isScrollingBlocked && index === 0
            readonly property bool isVisuallyEnlarged: isCurrent || isFakeSelected

            readonly property bool isVideo: safeFileName.startsWith("000_")
            readonly property bool matchesFilter: window.checkItemMatchesFilter(safeFileName, isVideo, window.cacheVersion, window.currentFilter)

            readonly property real targetWidth: isVisuallyEnlarged ? (window.itemWidth * 1.5) : (window.itemWidth * 0.5)
            readonly property real targetHeight: isVisuallyEnlarged ? (window.itemHeight + window.s(30)) : window.itemHeight

            property bool isPlayingVideo: false

            Timer {
                id: videoPlayTimer
                interval: 250
                running: delegateRoot.isVisuallyEnlarged && delegateRoot.isVideo && !window.isScrollingBlocked && !window.isFilterAnimating && !window.isItemAnimating
                onTriggered: {
                    if (delegateRoot.isVisuallyEnlarged && delegateRoot.isVideo) {
                        delegateRoot.isPlayingVideo = true;
                    }
                }
            }

            onIsVisuallyEnlargedChanged: {
                if (!isVisuallyEnlarged) {
                    isPlayingVideo = false;
                    videoPlayTimer.stop();
                }
            }

            width: matchesFilter ? (targetWidth + window.spacing) : 0
            visible: width > 0.1 || opacity > 0.01
            opacity: matchesFilter ? (isVisuallyEnlarged ? 1.0 : 0.6) : 0.0

            scale: matchesFilter ? 1.0 : 0.5

            height: matchesFilter ? targetHeight : 0
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            anchors.verticalCenterOffset: window.s(15)

            z: isVisuallyEnlarged ? 10 : 1

            Behavior on scale { enabled: window.initialFocusSet; NumberAnimation { duration: _theme.duration; easing.type: Easing.InOutQuad } }
            Behavior on width { enabled: window.initialFocusSet; NumberAnimation { duration: _theme.duration; easing.type: Easing.InOutQuad } }
            Behavior on height { enabled: window.initialFocusSet; NumberAnimation { duration: _theme.duration; easing.type: Easing.InOutQuad } }
            Behavior on opacity { enabled: window.initialFocusSet; NumberAnimation { duration: _theme.duration; easing.type: Easing.InOutQuad } }

            Item {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: ((window.itemHeight - height) / 2) * window.skewFactor

                width: parent.width > 0 ? parent.width * (targetWidth / (targetWidth + window.spacing)) : 0
                height: parent.height

                transform: Matrix4x4 {
                    property real s: window.skewFactor
                    matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: delegateRoot.matchesFilter && !window.isScrollingBlocked && !window.isApplying
                    onClicked: {
                        view.currentIndex = index
                        window.applyWallpaper(delegateRoot.safeFileName, delegateRoot.isVideo)
                    }
                }

                Image {
                    anchors.fill: parent
                    source: delegateRoot.matchesFilter && fileUrl !== undefined ? fileUrl : ""
                    sourceSize: Qt.size(16, 16)
                    fillMode: Image.Stretch
                    visible: true
                    asynchronous: true
                }

                Item {
                    anchors.fill: parent
                    anchors.margins: window.borderWidth
                    Rectangle { anchors.fill: parent; color: _theme.base }
                    clip: true

                    Image {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: window.s(-50)
                        width: (window.itemWidth * 1.5) + ((window.itemHeight + window.s(30)) * Math.abs(window.skewFactor)) + window.s(50)
                        height: window.itemHeight + window.s(30)
                        sourceSize.height: 420
                        fillMode: Image.PreserveAspectCrop
                        source: delegateRoot.matchesFilter && fileUrl !== undefined ? fileUrl : ""
                        asynchronous: true

                        transform: Matrix4x4 {
                            property real s: -window.skewFactor
                            matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }
                    }

                    Loader {
                        id: videoLoader
                        anchors.fill: parent
                        active: delegateRoot.isVideo && delegateRoot.isPlayingVideo
                        sourceComponent: Item {
                            anchors.fill: parent
                            MediaPlayer {
                                id: previewPlayer
                                source: "file://" + window.srcDir + "/" + window.getCleanName(delegateRoot.safeFileName)
                                audioOutput: AudioOutput { muted: true }
                                videoOutput: previewOutput
                                loops: MediaPlayer.Infinite
                                Component.onCompleted: play()
                            }
                            VideoOutput {
                                id: previewOutput
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: window.s(-50)
                                width: (window.itemWidth * 1.5) + ((window.itemHeight + window.s(30)) * Math.abs(window.skewFactor)) + window.s(50)
                                height: window.itemHeight + window.s(30)
                                fillMode: VideoOutput.PreserveAspectCrop
                                transform: Matrix4x4 {
                                    property real s: -window.skewFactor
                                    matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: delegateRoot.isVideo && !delegateRoot.isPlayingVideo
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: window.s(10)
                        width: window.s(32)
                        height: window.s(32)
                        radius: window.s(6)
                        color: Qt.rgba(_theme.base.r, _theme.base.g, _theme.base.b, 0.6)
                        transform: Matrix4x4 {
                            property real s: -window.skewFactor
                            matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "󰐊"
                            font.family: _theme.fontFamily
                            font.pixelSize: window.s(16)
                            color: _theme.text
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: filterBarBackground
        anchors.top: parent.top

        anchors.topMargin: window.isReady ? window.s(40) : window.s(-100)
        opacity: window.isReady ? 1.0 : 0.0
        Behavior on anchors.topMargin { NumberAnimation { duration: _theme.duration; easing.type: Easing.OutExpo } }
        Behavior on opacity { NumberAnimation { duration: _theme.duration; easing.type: Easing.OutCubic } }

        anchors.horizontalCenter: parent.horizontalCenter
        z: 20
        height: window.s(56)
        width: filterRow.width + window.s(24)
        radius: _theme.panelRadius

        color: _theme.panel
        border.color: _theme.border
        border.width: 1

        Row {
            id: filterRow
            anchors.centerIn: parent
            spacing: window.s(12)

            Rectangle {
                id: notifDrawer
                height: window.s(44)
                property real paddingLeft: window.showSpinner ? window.s(40) : window.s(16)
                property real targetWidth: window.showNotification ? Math.min(notifTextDrawer.implicitWidth + paddingLeft + window.s(20), window.s(300)) : 0
                width: targetWidth
                visible: width > 0.1
                radius: _theme.controlRadius
                clip: true
                anchors.verticalCenter: parent.verticalCenter

                color: window.showNotification ? _theme.control : "transparent"
                border.color: window.showNotification ? _theme.border : "transparent"
                border.width: 1

                Behavior on width {
                    NumberAnimation { duration: _theme.duration; easing.type: Easing.OutCubic }
                }
                Behavior on color { ColorAnimation { duration: _theme.duration } }
                Behavior on border.color { ColorAnimation { duration: _theme.duration } }

                Text {
                    id: notifSpinner
                    visible: window.showSpinner
                    anchors.left: parent.left
                    anchors.leftMargin: window.s(14)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰑐"
                    font.family: _theme.fontFamily
                    font.pixelSize: window.s(16)
                    color: _theme.accent

                    RotationAnimation on rotation {
                        loops: Animation.Infinite
                        from: 0; to: 360
                        duration: 900
                        running: window.showSpinner && window.showNotification
                    }
                }

                Text {
                    id: notifTextDrawer
                    anchors.left: parent.left
                    anchors.leftMargin: window.showSpinner ? window.s(40) : window.s(16)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, window.s(300) - anchors.leftMargin - window.s(16))
                    text: window.currentNotification

                    color: _theme.text
                    font.family: _theme.fontFamily
                    font.pixelSize: window.s(12)
                    font.bold: true
                    elide: Text.ElideRight

                    opacity: window.showNotification ? 0.95 : 0.0
                    Behavior on opacity { NumberAnimation { duration: _theme.duration; easing.type: Easing.OutQuad } }
                    Behavior on anchors.leftMargin {
                        NumberAnimation { duration: _theme.duration; easing.type: Easing.OutCubic }
                    }
                }
            }

            Rectangle {
                id: monitorDrawer
                visible: monitorModel.count > 1
                height: window.s(44)

                property real expandedWidth: window.s(44) + monitorListRow.width + window.s(8)
                width: visible ? (window.isMonitorSelectorOpen ? expandedWidth : window.s(44)) : 0

                radius: _theme.controlRadius
                clip: true
                anchors.verticalCenter: parent.verticalCenter

                color: window.isMonitorSelectorOpen ? _theme.control : "transparent"
                border.color: window.isMonitorSelectorOpen ? _theme.accent : _theme.border
                border.width: 1

                Behavior on width { NumberAnimation { duration: _theme.duration; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: _theme.duration } }
                Behavior on border.color { ColorAnimation { duration: _theme.duration } }

                MouseArea {
                    id: monitorIconMouse
                    width: window.s(44)
                    height: window.s(44)
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    hoverEnabled: true
                    enabled: !window.isApplying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: window.isMonitorSelectorOpen = !window.isMonitorSelectorOpen
                }

                Text {
                    id: monitorIcon
                    anchors.centerIn: monitorIconMouse
                    text: "󰍹"
                    font.family: _theme.fontFamily
                    font.pixelSize: window.s(16)
                    color: window.isMonitorSelectorOpen ? _theme.accent : (monitorIconMouse.containsMouse ? _theme.text : _theme.muted)
                }

                Row {
                    id: monitorListRow
                    anchors.left: monitorIconMouse.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: window.s(8)

                    opacity: window.isMonitorSelectorOpen ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: _theme.duration } }

                    Repeater {
                        model: monitorModel
                        delegate: Item {
                            width: monitorText.contentWidth + window.s(16)
                            height: window.s(32)
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                anchors.fill: parent
                                radius: _theme.controlRadius
                                color: model.selected ? _theme.accent : _theme.control
                                border.color: model.selected ? _theme.accent : _theme.border
                                border.width: 1

                                Behavior on color { ColorAnimation { duration: _theme.duration } }
                                Behavior on border.color { ColorAnimation { duration: _theme.duration } }

                                Text {
                                    id: monitorText
                                    text: model.name
                                    anchors.centerIn: parent
                                    color: model.selected ? _theme.base : _theme.text
                                    font.family: _theme.fontFamily
                                    font.pixelSize: window.s(11)
                                    font.bold: model.selected
                                    Behavior on color { ColorAnimation { duration: _theme.duration } }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: window.isMonitorSelectorOpen && !window.isApplying
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (model.selected) {
                                        let activeCount = 0;
                                        for (let i = 0; i < monitorModel.count; i++) {
                                            if (monitorModel.get(i).selected) activeCount++;
                                        }
                                        if (activeCount > 1) {
                                            monitorModel.setProperty(index, "selected", false);
                                        }
                                    } else {
                                        monitorModel.setProperty(index, "selected", true);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Repeater {
                model: window.filterData

                delegate: Item {
                    visible: modelData.name !== "Search"
                    width: !visible ? 0 : ((modelData.name === "Video" || modelData.name === "All") ? window.s(44) : (modelData.hex === "" ? filterText.contentWidth + window.s(24) : window.s(36)))
                    height: !visible ? 0 : window.s(36)
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: modelData.hex === "" ? _theme.controlRadius : (width / 2)
                        color: modelData.hex === ""
                                ? (window.currentFilter === modelData.name ? _theme.control : "transparent")
                                : modelData.hex

                        border.color: window.currentFilter === modelData.name ? _theme.accent : (modelData.hex === "" ? _theme.border : "transparent")
                        border.width: window.currentFilter === modelData.name ? window.s(2) : (modelData.hex === "" ? 1 : 0)
                        scale: window.currentFilter === modelData.name ? 1.12 : (filterMouse.containsMouse ? 1.06 : 1.0)

                        Behavior on scale { NumberAnimation { duration: _theme.duration; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: _theme.duration } }

                        Text {
                            id: filterText
                            visible: modelData.hex === "" && modelData.name !== "Video" && modelData.name !== "All"
                            text: modelData.label
                            anchors.centerIn: parent
                            color: window.currentFilter === modelData.name ? _theme.text : _theme.muted
                            font.family: _theme.fontFamily
                            font.pixelSize: window.s(12)
                            font.bold: window.currentFilter === modelData.name
                            Behavior on color { ColorAnimation { duration: _theme.duration; easing.type: Easing.OutQuart } }
                        }

                        Text {
                            visible: modelData.name === "Video"
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: 1
                            text: "󰐊"
                            font.family: _theme.fontFamily
                            font.pixelSize: window.s(14)
                            color: window.currentFilter === "Video" ? _theme.accent : (filterMouse.containsMouse ? _theme.text : _theme.muted)
                        }

                        Text {
                            visible: modelData.name === "All"
                            anchors.centerIn: parent
                            text: "󰕰"
                            font.family: _theme.fontFamily
                            font.pixelSize: window.s(14)
                            color: window.currentFilter === "All" ? _theme.accent : (filterMouse.containsMouse ? _theme.text : _theme.muted)
                        }
                    }

                    MouseArea {
                        id: filterMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !window.isApplying
                        onClicked: window.currentFilter = modelData.name
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }

            Rectangle {
                id: searchControlBtn
                visible: window.currentFilter === "Search" && window.hasSearched
                width: visible ? window.s(44) : 0
                height: window.s(44)
                radius: _theme.controlRadius
                clip: true
                anchors.verticalCenter: parent.verticalCenter
                color: window.isSearchPaused ? _theme.control : "transparent"
                border.color: window.isSearchPaused ? _theme.accent : _theme.border
                border.width: 1

                Behavior on width { NumberAnimation { duration: _theme.duration; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: _theme.duration; easing.type: Easing.OutQuart } }

                MouseArea {
                    id: scMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !window.isApplying
                    cursorShape: Qt.PointingHandCursor
                    onClicked: window.isSearchPaused = !window.isSearchPaused
                }

                Text {
                    anchors.centerIn: parent
                    text: window.isSearchPaused ? "󰐊" : "󰏤"
                    font.family: _theme.fontFamily
                    font.pixelSize: window.s(16)
                    color: window.isSearchPaused ? _theme.accent : (scMouse.containsMouse ? _theme.text : _theme.muted)
                }
            }

            Rectangle {
                id: searchBox
                height: window.s(44)
                width: window.currentFilter === "Search" ? window.s(360) : window.s(44)
                radius: _theme.controlRadius
                clip: true
                anchors.verticalCenter: parent.verticalCenter

                color: window.currentFilter === "Search" ? _theme.control : "transparent"
                border.color: window.currentFilter === "Search" ? _theme.accent : _theme.border
                border.width: 1

                Behavior on width { NumberAnimation { duration: _theme.duration; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: _theme.duration; easing.type: Easing.OutQuart } }
                Behavior on border.color { ColorAnimation { duration: _theme.duration } }

                Item {
                    id: searchIconBox
                    width: window.s(44)
                    height: window.s(44)
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "󰍉"
                        font.family: _theme.fontFamily
                        font.pixelSize: window.s(16)
                        color: window.currentFilter === "Search" ? _theme.accent : (searchIconMouse.containsMouse ? _theme.text : _theme.muted)
                    }

                    MouseArea {
                        id: searchIconMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !window.isApplying
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (window.currentFilter !== "Search") {
                                window.currentFilter = "Search";
                                searchInput.forceActiveFocus();
                            } else {
                                window.currentFilter = "All";
                            }
                        }
                    }
                }

                TextInput {
                    id: searchInput
                    anchors.left: searchIconBox.right
                    anchors.right: submitBtn.left
                    anchors.leftMargin: window.s(2)
                    anchors.rightMargin: window.s(8)
                    anchors.verticalCenter: parent.verticalCenter

                    opacity: window.currentFilter === "Search" ? 1.0 : 0.0
                    visible: opacity > 0
                    selectByMouse: true
                    selectionColor: _theme.accent
                    selectedTextColor: _theme.base
                    color: _theme.text
                    font.family: _theme.fontFamily
                    font.pixelSize: _theme.fontBody
                    clip: true

                    onTextEdited: {
                        window.hasSearched = false;
                        searchState.searched = false;
                    }

                    onAccepted: {
                        window.triggerOnlineSearch();
                        searchInput.focus = false;
                        view.forceActiveFocus();
                    }
                }

                Rectangle {
                    id: submitBtn
                    width: window.s(32)
                    height: window.s(32)
                    radius: _theme.controlRadius
                    anchors.right: parent.right
                    anchors.rightMargin: window.s(6)
                    anchors.verticalCenter: parent.verticalCenter

                    opacity: window.currentFilter === "Search" ? 1.0 : 0.0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: _theme.duration; easing.type: Easing.OutQuad } }

                    color: submitMouseArea.containsMouse ? _theme.border : "transparent"
                    border.color: submitMouseArea.containsMouse ? _theme.accent : _theme.border
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: _theme.duration } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰅂"
                        font.family: _theme.fontFamily
                        font.pixelSize: window.s(16)
                        color: submitMouseArea.containsMouse ? _theme.accent : _theme.muted
                    }

                    MouseArea {
                        id: submitMouseArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        enabled: !window.isApplying
                        onClicked: window.triggerOnlineSearch()
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        window.loadMonitors();
        window.triggerThumbnailGeneration();

        if (searchState.searched) {
            searchInput.text = searchState.query;
            window.searchQuery = searchState.query;
            window.hasSearched = true;
            window.lastSearchName = searchState.lastName;
            window.isSearchPaused = true;
        }

        view.forceActiveFocus();
        window.processMarkers();
    }

    Component.onDestruction: {
        if (thumbnailProcess.running) thumbnailProcess.signal(15);
        Quickshell.execDetached([Quickshell.shellDir + "/search-control.sh", "stop"]);
    }
}
