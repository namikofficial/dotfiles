// UpdateModel — package update availability for the top bar.
// Polls hypr/scripts/status-updates.sh (the same source the Wayle fallback
// shell uses) every 60 seconds and publishes {"count":N,"text":"N","tooltip":"…"}.
// Properties: count, tooltip, checked, available. refresh() re-polls on demand.

import QtQml
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property int count: 0
    property string tooltip: ""
    property bool checked: false
    readonly property bool available: root.count > 0

    property Timer pollTimer: Timer {
        id: pollTimer
        interval: 60000
        repeat: true
        onTriggered: root.poll()
    }

    function start() { pollTimer.restart(); root.poll(); }
    function stop() { pollTimer.stop(); }

    function refresh() { root.poll(); }

    function poll() {
        if (procUpdate.running) return;
        procUpdate.running = false;
        procUpdate.running = true;
    }

    property Process procUpdate: Process {
        id: procUpdate
        running: false
        command: ["sh", "-c", "exec \"$HOME/.config/hypr/scripts/status-updates.sh\" 2>/dev/null || printf '{\"count\":0,\"text\":\"0\",\"tooltip\":\"Update status unavailable\"}'"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                var line = String(data).trim();
                if (!line) return;
                try {
                    var state = JSON.parse(line);
                    if (state && state.count !== undefined) {
                        root.count = Math.max(0, parseInt(state.count, 10) || 0);
                        root.tooltip = String(state.tooltip || "");
                        root.checked = true;
                    }
                } catch (error) {
                    // Malformed output — keep last known state but mark checked
                    // so the bar pill settles instead of flashing.
                    root.checked = true;
                }
            }
        }
    }
}
