// NotificationModel — local notification store.
// Merges daemon-sourced notifications (via noxd provider) with local ones.
// Acts like a ProviderModel for Protocol.js compatibility, but keeps its own list.
// DMS + Tide steal: grouped by app, DND, history, inline actions.

import QtQml
import "ModelUtils.js" as Utils

QtObject {
    id: root

    property string providerName: "notifications"
    property string status: "available"
    readonly property bool available: status === "available"

    // ── State ──
    property bool dnd: false
    property var notifications: []      // active notifications
    property var history: []            // dismissed/expired (max 50)
    property int maxActive: 20
    property int maxHistory: 50
    property int nextId: 1

    // ── Signals (names prefixed to avoid clashing with property change signals) ──
    signal sigNotificationAdded(var notification)
    signal sigNotificationRemoved(int id)
    signal sigNotificationDismissed(int id)
    signal sigDndChanged(bool enabled)

    // ── Public API ──
    function addNotification(appName, summary, body, icon, urgency, actions, timeout) {
        if (dnd && urgency !== "critical") return;

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
            timeout: timeout || 5000,
            timestamp: new Date().toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
        };

        // Trim active list
        while (notifications.length >= maxActive) {
            var removed = notifications.shift();
            pushHistory(removed);
        }

        notifications.push(notification);
        sigNotificationAdded(notification);
        return notification.id;
    }

    function dismissNotification(id) {
        var idx = findIndex(id);
        if (idx < 0) return false;
        var note = notifications[idx];
        notifications.splice(idx, 1);
        sigNotificationRemoved(id);
        sigNotificationDismissed(id);
        pushHistory(note);
        return true;
    }

    function clearAll() {
        while (notifications.length > 0) {
            var note = notifications.shift();
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
        history.unshift(note);
        while (history.length > maxHistory) history.pop();
    }

    function toggleDnd() {
        dnd = !dnd;
        sigDndChanged(dnd);
    }

    // ── Provider-style snapshot (for daemon compatibility) ──
    function applySnapshot(snapshot) {
        if (!Utils.applyBase(this, snapshot, providerName)) return false;
        var next = snapshot.data;
        if (Array.isArray(next.items)) {
            notifications = next.items;
        }
        dnd = next.dnd === true;
        return true;
    }
}
