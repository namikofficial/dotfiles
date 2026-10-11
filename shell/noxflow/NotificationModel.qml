// NotificationModel — the shell's notification store.
//
// Decision 5: Quickshell owns org.freedesktop.Notifications and dunst is
// retired, so this is a plain in-memory store fed by services/NotificationBridge
// with Do Not Disturb as one property right here.
//
// It used to carry two dead paths: a `dunstctl` query and setter for DND, and a
// noxd `notifications` provider snapshot. noxd registers no such provider, so
// `applySnapshot` could never fire — and `addNotification` had no caller at all,
// which is why the bar's notification pill and the notification centre rendered
// permanently empty while looking perfectly healthy.

import QtQml
import Quickshell
import "ModelUtils.js" as Utils

QtObject {
    id: root

    property string providerName: "notifications"
    // Quickshell's NotificationServer is the ingress. `source` stays
    // "quickshell" so the views and the log can say which daemon owns the bus.
    property string source: "quickshell"
    property string ingressStatus: "quickshell"
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
        var notification = {
            id: nextId++,
            app_name: appName || "",
            app_icon: icon || "",
            summary: summary || "",
            body: body || "",
            urgency: urgency || "normal",
            time: Date.now(),
            actions: Utils.asArray(actions),
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

    /// Toggle Do Not Disturb. This is the single write path: there is no
    /// daemon to ask, so the property *is* the state.
    function toggleDnd() {
        root.dnd = !root.dnd;
        root.sigDndChanged(root.dnd);
    }

    function setDnd(enabled) {
        if (root.dnd === !!enabled) return;
        root.dnd = !!enabled;
        root.sigDndChanged(root.dnd);
    }

    property string dndOutput: ""

    /// Replace the whole active list from the bridge. The bridge owns the live
    /// set, so this replaces rather than merges — a merge would leave notes
    /// behind that the server no longer holds.
    function replaceAll(items, dndEnabled) {
        if (dndEnabled !== undefined) root.dnd = !!dndEnabled;
        var next = [];
        var history = root.history;
        for (var i = 0; i < items.length; i++) {
            var note = items[i];
            // DND suppresses presentation but keeps the note in history, the
            // same rule addNotification() has always used.
            if (root.dnd && note.urgency !== "critical") {
                history = [note].concat(history).slice(0, root.maxHistory);
                continue;
            }
            next.push(note);
        }
        notifications = next;
        history = history;
    }

    /// Called when DND flips so already-visible notes are pulled back.
    function applyDnd(enabled) {
        if (root.dnd === enabled) return;
        root.dnd = enabled;
        if (!enabled) return;
        var history = root.history;
        var keep = [];
        for (var i = 0; i < root.notifications.length; i++) {
            var note = root.notifications[i];
            if (note.urgency === "critical") keep.push(note);
            else history = [note].concat(history);
        }
        notifications = keep;
        history = history.slice(0, root.maxHistory);
        root.sigDndChanged(enabled);
    }
}
