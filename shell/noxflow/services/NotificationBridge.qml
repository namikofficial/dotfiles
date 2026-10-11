import QtQml
import QtQuick
import Quickshell
import Quickshell.Services.Notifications as Notify

// NotificationBridge.qml — the shell's org.freedesktop.Notifications owner.
//
// Decision 5: Quickshell owns notifications and dunst is retired, so there is
// one place for Do Not Disturb instead of three disagreeing write paths.
//
// Before this existed the notification pill and the notification centre
// rendered permanently empty: NotificationModel had no producer at all
// (`addNotification` had zero callers) and noxd registers no `notifications`
// provider, so the subscription Phase 2 removed was correct — but nothing
// replaced it. This is the replacement.
//
// ── How this Quickshell build actually behaves ──
// Everything here was established by measurement against quickshell 0.3.2, not
// from the docs, and three of the four obvious approaches do not work:
//
//   * `NotificationServer` is **not** usable as a bare singleton reference.
//     `NotificationServer.trackedNotifications` evaluates to `undefined` and
//     the DBus name is never claimed. It must be instantiated as an object;
//     only then does the server start and register.
//   * `trackedNotifications` is a QAbstractItemModel whose `rowCount()` stays
//     **0 even while a notification is live**. Wiring a Repeater to it — the
//     obvious way to learn about inserts and removes — yields a model that
//     silently produces zero delegates, forever. It is not an error, it is
//     just empty. Do not use it.
//   * The server exposes exactly one signal, `notification(Notification)`.
//     There is no `dismissed` signal and no `objectInserted`/`objectRemoved`
//     on the model — and `Notification.closed(reason)`, though it exists, is
//     never emitted, because the server never tracks what it hands to QML.
//     Measured: a notification sent with a 2000 ms expire_timeout was still
//     live ten seconds later, and a sender-initiated CloseNotification on the
//     DBus interface produced no `closed` either.
//
// So arrivals come from the `notification` signal and departures are owned by
// this file: a one-second sweep retires whatever has outlived its
// expire_timeout, and a dismiss here calls `Notification.dismiss()` so the
// sending application is still told. The one thing that cannot be observed is a
// sender closing its own notification behind our back; such a notification stays
// until its timeout. That is a real limitation of retiring dunst and is
// documented rather than papered over.
//
// Do Not Disturb is enforced here rather than by pausing a daemon. This
// NotificationServer has no pause API, so DND suppresses *presentation* and
// keeps the notification in history. A suppressed notification is not dropped
// — that is weaker than dunst's true pause and is the documented cost of
// retiring dunst.

Item {
    id: root

    // ── Inputs ──
    required property var model          // NotificationModel.qml

    // ── The notification server ──
    // Instantiated, never referenced as a singleton — see the note above.
    Notify.NotificationServer {
        id: server
    }

    // ── Do Not Disturb ──
    // One property on one model. dunstctl set-paused/is-paused are gone.
    readonly property bool dnd: root.model ? root.model.dnd : false

    onDndChanged: {
        // Re-evaluate presentation: a notification already on screen when DND
        // turns on is pulled back to history rather than left visible.
        if (root.model) root.model.applyDnd(root.dnd);
    }

    // ── Live set ──
    // Keyed by the server's own notification id so a replacement of the same
    // id updates in place instead of duplicating.
    //
    // `live`, `deadline` and `order` are deliberately plain JS structures. They
    // are only ever read imperatively — never from a binding — because QML
    // cannot observe a key being written into a JS object. Anything that needs
    // to react goes through `order`, which *is* a property assignment.
    property var live: ({})          // id -> Notification object
    property var deadline: ({})      // id -> epoch ms at which it expires
    property var order: []            // ids, oldest first

    readonly property int count: root.order.length

    // Expiry is owned here, not by the server. Quickshell 0.3.2 does not track
    // notifications it hands to QML (trackedNotifications.rowCount() stays 0),
    // and consequently never expires them or emits `closed` — measured, not
    // assumed: a 2-second expire_timeout notification was still on the bus
    // ten seconds later. One sweep a second is enough for a badge and costs
    // nothing measurable; the alternative, a per-notification delegate holding a
    // Connections to `closed`, is both slower and provably dead on this build.
    readonly property int sweepIntervalMs: 1000
    readonly property int defaultTimeoutMs: 5000

    Timer {
        interval: root.sweepIntervalMs
        running: true
        repeat: true
        onTriggered: root.sweep()
    }

    function timeoutOf(entry) {
        // The spec's expire_timeout: -1 means "never", 0 means "server picks".
        var ms = entry && entry.expireTimeout !== undefined ? Number(entry.expireTimeout) : 0;
        if (!(ms > 0)) return root.defaultTimeoutMs;
        return ms;
    }

    function sweep() {
        var now = Date.now();
        var expired = [];
        for (var i = 0; i < root.order.length; i++) {
            var key = root.order[i];
            var due = root.deadline[key];
            if (due !== undefined && now >= due) expired.push(key);
        }
        for (var j = 0; j < expired.length; j++) {
            var gone = root.live[expired[j]];
            // Tell the sender its notification went away before dropping it.
            if (gone && typeof gone.dismiss === "function") gone.dismiss();
            root.remove(expired[j]);
        }
    }

    function upsert(entry) {
        if (!entry) return;
        var key = String(entry.id);
        var isNew = root.live[key] === undefined;
        root.live[key] = entry;
        // A replacement restarts the clock; the sender is still showing it.
        root.deadline[key] = Date.now() + root.timeoutOf(entry);
        if (isNew) root.order = root.order.concat([key]);
        root.publish();
    }

    function remove(id) {
        var key = String(id);
        if (root.live[key] === undefined) return;
        delete root.live[key];
        delete root.deadline[key];
        root.order = root.order.filter(function (k) { return k !== key; });
        root.publish();
    }

    function find(id) {
        var key = String(id);
        return root.live[key] !== undefined ? root.live[key] : null;
    }

    function clearAll() {
        root.live = {};
        root.deadline = {};
        root.order = [];
        root.publish();
    }

    // ── Arrivals ──
    Connections {
        target: server
        function onNotification(n) {
            root.upsert(n);
        }
    }

    // ── Translation ──

    /// Push the live set into NotificationModel, newest first.
    function publish() {
        if (!root.model) return;
        var out = [];
        for (var i = root.order.length - 1; i >= 0; i--) {
            var entry = root.live[root.order[i]];
            if (entry) out.push(root.toNote(entry));
        }
        root.model.replaceAll(out, root.dnd);
    }

    /// `NotificationUrgency::Enum` is Low=0, Normal=1, Critical=2 — it is not
    /// the spec's 0/1/2 numeric field, so it must be mapped explicitly.
    function urgencyOf(entry) {
        if (!entry || entry.urgency === undefined || entry.urgency === null) return "normal";
        if (entry.urgency === 2) return "critical";
        if (entry.urgency === 0) return "low";
        return "normal";
    }

    function toNote(entry) {
        var actions = [];
        if (entry.actions) {
            for (var i = 0; i < entry.actions.length; i++) {
                var a = entry.actions[i];
                // NotificationAction exposes `identifier`/`text`; the views
                // want `id`/`label`.
                actions.push({
                    id: String(a.identifier),
                    label: String(a.text || "")
                });
            }
        }
        return {
            id: String(entry.id),
            server_id: String(entry.id),
            app_name: entry.appName || "",
            app_icon: entry.appIcon || "",
            summary: entry.summary || "",
            body: entry.body || "",
            urgency: root.urgencyOf(entry),
            time: Date.now(),
            actions: actions,
            dismissable: true,
            timeout: entry.expireTimeout === undefined ? 5000 : Number(entry.expireTimeout)
        };
    }

    // ── Commands ──
    // Dismiss tells the server first, so the sending application learns its
    // notification went away rather than being left waiting, and only then
    // drops it locally. Nothing comes back to confirm it (see the header), so
    // the local removal is not conditional on a `closed` signal.
    function dismiss(id) {
        var entry = root.find(id);
        if (entry && typeof entry.dismiss === "function") entry.dismiss();
        root.remove(id);
    }

    function invoke(id, actionId) {
        var entry = root.find(id);
        if (!entry || !entry.actions) return false;
        for (var i = 0; i < entry.actions.length; i++) {
            var a = entry.actions[i];
            if (String(a.identifier) === String(actionId) && typeof a.invoke === "function") {
                a.invoke();
                return true;
            }
        }
        return false;
    }

    function closeAll() {
        var ids = root.order.slice();
        for (var i = 0; i < ids.length; i++) {
            var entry = root.live[ids[i]];
            if (entry && typeof entry.dismiss === "function") entry.dismiss();
        }
        root.clearAll();
    }
}