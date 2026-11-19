// WallpaperModel — indexes wallpaper files from the configured directories.
// Reuses set-wallpaper.sh's WALLPAPER_DIRS convention. Asynchronous scan via
// Process; no shell-command polling.

import QtQml
import Quickshell
import Quickshell.Io
import "WallpaperScan.js" as WallpaperScan
import "components" as Components

QtObject {
    id: root

    property var walls: []
    property bool scanning: false
    property string error: ""
    property string current: ""

    // Mirrors hypr/scripts/set-wallpaper.sh wall_dirs (env override supported).
    readonly property string wallDirs: {
        var env = Quickshell.env("WALLPAPER_DIRS");
        if (env) return env;
        var home = Quickshell.env("HOME");
        return home + "/Pictures/wallpaper/handpicked/1080p:" + home + "/Pictures/wallpaper/handpicked/4k";
    }

    property Components.Command scanProc: Components.Command {
        label: "Wallpaper scan"
        onExited: function(code) { root._onScanData(code, root.scanProc.output) }
    }
    property Components.Command currentProc: Components.Command {
        label: "Current wallpaper"
        onExited: function(code) {
            if (code === 0) root.current = root.currentProc.output.trim();
        }
    }

    // ── Scan ──
    function scan() {
        if (scanning) return;
        scanning = true;
        error = "";
        var dirs = root.wallDirs.split(":");
        var roots = [];
        for (var i = 0; i < dirs.length; i++) {
            if (dirs[i].trim()) roots.push(dirs[i].trim());
        }
        if (roots.length === 0) {
            scanning = false;
            error = "";
            walls = [];
            return;
        }
        scanProc.run(WallpaperScan.argumentsFor(roots));
    }

    /// Empty directories are a valid empty state; only a failed find is an error.
    function _onScanData(exitCode, data) {
        scanning = false;
        var scanned = WallpaperScan.result(exitCode, data);
        error = scanned.error;
        walls = scanned.walls;
    }

    // ── Current wallpaper ──
    function readCurrent() {
        var home = Quickshell.env("HOME");
        // No `|| true` and no 2>/dev/null: Command records the exit code, so a
        // missing cache file is visible instead of looking like an empty answer.
        currentProc.run(["cat", home + "/.cache/current-wallpaper"]);
    }

    // ── Apply ──
    // Delegates to the existing set-wallpaper.sh (handles hyprpaper + matugen
    // + notifications). No fake success: the exit code propagates.
    property Components.Command applyProc: Components.Command { label: "Apply wallpaper" }
    property Components.Command themePassProc: Components.Command { label: "Theme pass" }

    function apply(path) {
        if (!path) return;
        var home = Quickshell.env("HOME");
        // 2>&1 merged stdout/stderr: the banner should show the script's own
        // explanation, not a bare exit code.
        applyProc.run(["sh", "-c", home + "/.config/hypr/scripts/set-wallpaper.sh " + JSON.stringify(path) + " 2>&1"]);
        readCurrent();
    }

    function runThemePass() {
        var home = Quickshell.env("HOME");
        // Fire and forget: theme-pass is a background job, not a command whose
        // result the UI reports.
        themePassProc.run(["sh", "-c", home + "/.config/hypr/scripts/theme-pass.sh >/dev/null 2>&1 &"]);
    }

    Component.onCompleted: {
        scan();
        readCurrent();
    }
}
