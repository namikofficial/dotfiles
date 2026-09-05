// WallpaperModel — indexes wallpaper files from the configured directories.
// Reuses set-wallpaper.sh's WALLPAPER_DIRS convention. Asynchronous scan via
// Process; no shell-command polling.

import QtQml
import Quickshell
import Quickshell.Io
import "ModelUtils.js" as Utils

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

    property Process scanProc: Process {
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) { root._onScanData(data); }
        }
    }
    property Process currentProc: Process {
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) { root._onCurrentData(data); }
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
        scanProc.command = ["sh", "-c",
            "find " + expr.join(" ") +
            " -maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) 2>/dev/null | sort -u"];
        scanProc.running = true;
    }

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
        currentProc.command = ["sh", "-c", "cat " + JSON.stringify(home) + "/.cache/current-wallpaper 2>/dev/null || true"];
        currentProc.running = true;
    }

    function _onCurrentData(data) {
        current = (data || "").trim();
    }

    // ── Apply ──
    // Delegates to the existing set-wallpaper.sh (handles hyprpaper + matugen
    // + notifications). No fake success: the exit code propagates.
    property Process applyProc: Process { running: false }
    property Process themePassProc: Process { running: false }

    function apply(path) {
        if (!path) return;
        var home = Quickshell.env("HOME");
        applyProc.command = ["sh", "-c", home + "/.config/hypr/scripts/set-wallpaper.sh " + JSON.stringify(path) + " 2>&1"];
        applyProc.running = true;
        readCurrent();
    }

    function runThemePass() {
        var home = Quickshell.env("HOME");
        themePassProc.command = ["sh", "-c", home + "/.config/hypr/scripts/theme-pass.sh >/dev/null 2>&1 &"];
        themePassProc.running = true;
    }

    Component.onCompleted: {
        scan();
        readCurrent();
    }
}
