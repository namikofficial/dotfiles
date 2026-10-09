// WallpaperModel — indexes wallpaper files from the configured directories.
// Reuses set-wallpaper.sh's WALLPAPER_DIRS convention. Asynchronous scan via
// Process; no shell-command polling.

import QtQml
import Quickshell
import Quickshell.Io
import "ModelUtils.js" as Utils
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
        onExited: function(code) { root._onScanData(code === 0 ? root.scanProc.output : "") }
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
        var expr = [];
        for (var i = 0; i < dirs.length; i++) {
            if (dirs[i]) expr.push("-E " + JSON.stringify(dirs[i]));
        }
        if (expr.length === 0) {
            scanning = false;
            walls = [];
            return;
        }
        scanProc.runShell(
            "find " + expr.join(" ") +
            " -maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) 2>/dev/null | sort -u");
    }

    /// Whole-output variant of the old line-by-line SplitParser handler.
    function _onScanData(data) {
        scanning = false;
        if (!data) {
            error = "wallpaper scan failed";
            walls = [];
            return;
        }
        var lines = data.split("\n").filter(function(l) { return l.trim() !== ""; });
        var rejected = /(^|[^a-z])(anime|waifu|manga|hentai|kawaii|girl|girls|woman|women|character|avatar|hollow[ -]?knight|game[-_ ]?art|fanart|illustration)([^a-z]|$)/i;
        lines = lines.filter(function(p) { return !rejected.test(p.split("/").pop()); });
        walls = lines.map(function(p) {
            var parts = p.split("/");
            return { path: p, name: parts[parts.length - 1] };
        });
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
