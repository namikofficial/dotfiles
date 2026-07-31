// TransferService — Quick Share frontend backed by LocalSend.
//
// HONEST INTEGRATION (per design contract §7):
// LocalSend is a Flutter GUI app. Its HTTP API server (port 53317) only
// answers /api/localsend/v2/info (own identity) and /register (discovery
// handshake). The file-transfer endpoints (prepare-upload/upload) run on the
// PEER's server and require per-peer discovery + certificate validation that
// only the LocalSend app implements.
//
// Therefore this service does NOT invent transfers. It:
//   1. probes daemon health (/info) and surfaces "daemon down" honestly,
//   2. offers to launch the LocalSend app when the user wants to send or
//      when the daemon is not running,
//   3. records a history of user-initiated send attempts with a truthful
//      state ("launched-app" → awaiting the app's own confirmation).
//
// The receiving workflow (accept/decline/progress) is handled by the
// LocalSend app's own UI and notifications, which is the correct ownership
// boundary. This panel is the launch point + status surface, not a fake
// transfer engine.

import QtQml
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // ── Daemon health ──
    property string daemonBase: "https://127.0.0.1:53317"
    property bool daemonUp: false
    property bool daemonChecked: false
    property string daemonAlias: ""
    property string daemonError: ""
    property bool checking: false

    // ── History of send attempts (truthful states) ──
    property var history: []
    property int maxHistory: 20

    // ── Processes ──
    property Process infoProbe: Process {
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) { root._onInfoData(data); }
        }
    }
    property Process launchProc: Process { running: false }

    property Timer refreshTimer: Timer {
        interval: 15000
        repeat: true
        running: root.refreshing
        onTriggered: root.checkDaemon()
    }
    property bool refreshing: false

    // ── Public API ──

    function checkDaemon() {
        if (checking) return;
        checking = true;
        infoProbe.command = ["curl", "-sk", "--max-time", "3", root.daemonBase + "/api/localsend/v2/info"];
        infoProbe.running = true;
    }

    function _onInfoData(data) {
        checking = false;
        var out = data || "";
        var ok = out.trim() !== "";
        daemonUp = ok;
        daemonChecked = true;
        if (ok) {
            try {
                var info = JSON.parse(out);
                daemonAlias = info.alias || "LocalSend";
                daemonError = "";
            } catch (e) {
                daemonUp = false;
                daemonError = "invalid daemon response";
            }
        } else {
            daemonError = "LocalSend daemon not reachable";
            daemonAlias = "";
        }
    }

    // Launch the LocalSend app (tray/GUI). Used both when the daemon is down
    // and as the send entry point — the app owns discovery, pairing, and the
    // actual transfer UI.
    function launchApp() {
        launchProc.command = ["sh", "-c", "/usr/bin/localsend >/dev/null 2>&1 &"];
        launchProc.running = true;
        _record({ id: "send-" + Date.now(), action: "open-app", state: "launched", createdAt: Date.now() });
    }

    // Record a user-initiated send intent. The actual transfer happens inside
    // the LocalSend app; we record the intent truthfully.
    function recordSendIntent() {
        _record({ id: "send-" + Date.now(), action: "send", state: "awaiting-app", createdAt: Date.now() });
    }

    function _record(t) {
        history = [t].concat(history);
        if (history.length > maxHistory) history = history.slice(0, maxHistory);
    }
}
