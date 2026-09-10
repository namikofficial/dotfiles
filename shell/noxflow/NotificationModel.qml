// NotificationModel — local notification store.
// Merges daemon-sourced notifications (via noxd provider) with local ones.
// Acts like a ProviderModel for Protocol.js compatibility, but keeps its own list.
// DMS + Tide steal: grouped by app, DND, history, inline actions.

import QtQml
import Quickshell
import Quickshell.Io
import "ModelUtils.js" as Utils

QtObject {
    id: root

    property string providerName: "notifications"
    // Dunst owns org.freedesktop.Notifications in this profile. NoxFlow's
    // model is a shell-local history/demo store until a non-conflicting bridge
    // is installed; it must not claim daemon-backed ingress.
    property string source: "dunst-owned"
    property string ingressStatus: "dunst-owned"
    property string status: "available"
    readonly property bool available: status === "available"

    // ── State ──
    property bool dnd: false
    property var notifications: []      // active notifications
    property var history: []            // dismissed/expired (max 50)
    property int maxActive: 20
    property int maxHistory: 50
    property int nextId: 1
    property bool dndQueryRunning: false
    property bool dndUpdateRunning: false

    // ── Signals (names prefixed to avoid clashing with property change signals) ──
    signal sigNotificationAdded(var notification)
    signal sigNotificationRemoved(int id)
    signal sigNotificationDismissed(int id)
    signal sigDndChanged(bool enabled)

    // ── Public API ──
    function addNotification(appName, summary, body, icon, urgency, actions, timeout) {
        var notification = {
            id: nextId++,
            app_name: appName || "",
            app_icon: icon || "",
            summary: summary || "",
            body: body || "",
            urgency: urgency || "normal",
            time: Date.now(),
            actions: Array.isArray(actions) ? actions : [],
            dismissable: true,
            timeout: timeout === undefined ? 5000 : Math.max(0, Number(timeout)),
            timestamp: new Date().toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
        };

        // DND suppresses presentation but retains the notification in history;
        // critical notifications remain visible immediately.
        if (dnd && urgency !== "critical") {
            pushHistory(notification);
            return notification.id;
        }

        // Trim active list
        while (notifications.length >= maxActive) {
            var removed = notifications.shift();
            pushHistory(removed);
        }

        notifications = notifications.concat([notification]);
        sigNotificationAdded(notification);
        return notification.id;
    }

    function dismissNotification(id) {
        var idx = findIndex(id);
        if (idx < 0) return false;
        var note = notifications[idx];
        notifications = notifications.slice(0, idx).concat(notifications.slice(idx + 1));
        sigNotificationRemoved(id);
        sigNotificationDismissed(id);
        pushHistory(note);
        return true;
    }

    function clearAll() {
        var active = notifications;
        notifications = [];
        for (var i = 0; i < active.length; i++) {
            var note = active[i];
            pushHistory(note);
        }
    }

    function clearHistory() {
        history = [];
    }

    function findIndex(id) {
        for (var i = 0; i < notifications.length; i++) {
            if (notifications[i].id === id) return i;
        }
        return -1;
    }

    function pushHistory(note) {
        var next = [note].concat(history);
        history = next.slice(0, maxHistory);
    }

    function toggleDnd() {
        if (dndUpdateRunning) return;
        dndUpdateRunning = true;
        dndProcess.command = ["dunstctl", "set-paused", dnd ? "false" : "true"];
        dndProcess.running = true;
    }

    function refreshDnd() {
        if (dndQueryRunning) return;
        dndQueryRunning = true;
        dndQuery.command = ["dunstctl", "is-paused"];
        dndQuery.running = true;
    }

    property string dndOutput: ""
    property Process dndQuery: Process {
        running: false
        stdout: SplitParser {
            splitMarker: ""
            onRead: function(data) { root.dndOutput += String(data || ""); }
        }
        onExited: function(code, status) {
            root.dndQueryRunning = false;
            if (code === 0) {
                var value = root.dndOutput.trim().toLowerCase();
                root.dnd = value === "true" || value === "1" || value === "paused";
                root.sigDndChanged(root.dnd);
            } else {
                root.ingressStatus = "dunst-unavailable";
            }
            root.dndOutput = "";
        }
    }
    property Process dndProcess: Process {
        running: false
        onExited: function(code, status) {
            root.dndUpdateRunning = false;
            if (code === 0) {
                root.ingressStatus = "dunst-owned";
                root.refreshDnd();
            } else {
                root.ingressStatus = "dunst-unavailable";
            }
        }
    }

    Component.onCompleted: refreshDnd()

    // ── Provider-style snapshot (for daemon compatibility) ──
    function applySnapshot(snapshot) {
        if (!Utils.applyBase(this, snapshot, providerName)) return false;
        var next = snapshot.data;
        if (Array.isArray(next.items)) {
            notifications = next.items.slice();
        }
        dnd = next.dnd === true;
        return true;
    }
}
