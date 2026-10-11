// UpdateModel — package update availability for the top bar.
// Polls hypr/scripts/status-updates.sh (the same source the Wayle fallback
// shell uses) every 60 seconds and publishes {"count":N,"text":"N","tooltip":"…"}.
// Properties: count, tooltip, checked, available. refresh() re-polls on demand.

import QtQml
import Quickshell
import Quickshell.Io
import "components" as Components

QtObject {
    id: root

    property int count: 0
    property string tooltip: ""
    // Set when the update script itself fails; empty means the last check worked.
    property string lastError: ""
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
        // stderr is deliberately NOT discarded: a failing script must say why.
        procUpdate.run(["sh", "-c", "exec \"$HOME/.config/hypr/scripts/status-updates.sh\""]);
    }

    property Components.Command procUpdate: Components.Command {
        label: "Update check"
        onExited: function(code) {
            if (code !== 0) {
                // Previously this command was
                //   "... 2>/dev/null || printf '{"count":0,...}'"
                // which turned every failure into a confident "0 updates" and
                // made a broken script indistinguishable from an up-to-date
                // machine. Now the failure is recorded instead.
                root.lastError = root.procUpdate.failureText();
                root.checked = true;   // let the pill settle rather than flash
                console.warn("updates:", root.lastError);
                return;
            }
            root.lastError = "";
            var line = root.procUpdate.output.trim().split("\n")[0] || "";
            if (!line) { root.checked = true; return; }
            try {
                var state = JSON.parse(line);
                if (state && state.count !== undefined) {
                    root.count = Math.max(0, parseInt(state.count, 10) || 0);
                    root.tooltip = String(state.tooltip || "");
                    root.checked = true;
                }
            } catch (error) {
                root.checked = true;
                console.warn("updates: malformed output:", line);
            }
        }
    }
}
