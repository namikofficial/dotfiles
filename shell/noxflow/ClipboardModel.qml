// Clipboard history model — stores recent clipboard entries.
// For now, starts empty and populates via launcher "Clipboard" mode.
// Future: use wl-paste watch or noxd clipboard provider for auto-capture.

import QtQml
import QtQuick
import Quickshell
import Quickshell.Io
import "ModelUtils.js" as Utils

QtObject {
    id: root

    property var history: []       // Array of {id, text, timestamp, source}
    property int maxHistory: 50
    readonly property int count: history.length

    // ── Add entry ──
    function addEntry(text, source) {
        if (!text || text.trim() === "") return null;

        // Deduplicate: if last entry is same text, just update timestamp
        if (history.length > 0 && history[0].text === text) {
            history[0].timestamp = Date.now();
            return history[0];
        }

        var entry = {
            id: "clip-" + Date.now() + "-" + Math.floor(Math.random() * 1000),
            text: text,
            timestamp: Date.now(),
            source: source || "clipboard",
        };

        history = [entry].concat(history);
        if (history.length > maxHistory) {
            history = history.slice(0, maxHistory);
        }

        root.save();
        return entry;
    }

    // ── Remove entry ──
    function removeEntry(id) {
        history = history.filter(function(e) { return e.id !== id; });
        root.save();
    }

    // ── Clear all ──
    function clearAll() {
        history = [];
        root.save();
    }

    // ── Persistence ──
    readonly property string storageDir: {
        var state = Quickshell.env("XDG_STATE_HOME");
        if (!state) state = Quickshell.env("HOME") + "/.local/state";
        return state + "/noxflow";
    }

    readonly property string storagePath: storageDir + "/clipboard.json"

    function load() {
        // FileView preloads on path set; onLoaded parses prior history if present.
        storageFile.path = root.storagePath;
    }

    function save() {
        try {
            pendingJson = JSON.stringify(history);
            storageFile.setText(pendingJson);
        } catch (e) {
            console.warn("clipboard: failed to save history", e);
        }
    }

    property string pendingJson: ""

    property FileView storageFile: FileView {
        id: storageFile
        path: root.storagePath
        watchChanges: false
        onLoaded: {
            try {
                var parsed = JSON.parse(storageFile.text());
                if (Array.isArray(parsed)) root.history = parsed;
            } catch (e) {
                // Corrupt JSON — start empty, that's fine.
            }
        }
        onLoadFailed: function(error) {
            // First run: file doesn't exist yet. Ensure dir for later writes.
            ensureDirProcess.running = true;
        }
        onSaveFailed: function(error) {
            console.warn("clipboard: save failed", error);
            ensureDirProcess.running = true;  // likely missing dir; retry next save
        }
    }

    property Process ensureDirProcess: Process {
        id: ensureDirProcess
        running: false
        command: ["mkdir", "-p", root.storageDir]
    }

    // ── Format helpers for launcher display ──
    function formatTime(timestamp) {
        var now = Date.now();
        var diff = now - timestamp;
        if (diff < 60000) return "just now";
        if (diff < 3600000) return Math.floor(diff / 60000) + "m ago";
        if (diff < 86400000) return Math.floor(diff / 3600000) + "h ago";
        return Math.floor(diff / 86400000) + "d ago";
    }

    function previewText(text) {
        var firstLine = text.split("\n")[0] || "";
        return firstLine.length > 60 ? firstLine.substring(0, 57) + "..." : firstLine;
    }

    // ── Get entries as launcher items ──
    function asLauncherItems(limit) {
        if (!limit) limit = 10;
        var items = [];
        for (var i = 0; i < Math.min(history.length, limit); i++) {
            var entry = history[i];
            items.push({
                title: previewText(entry.text),
                icon: "◆",
                subtitle: formatTime(entry.timestamp),
                action: "copy_to_clipboard",
                actionParams: { text: entry.text },
                entryId: entry.id,
            });
        }
        return items;
    }

    Component.onCompleted: root.load()
}
