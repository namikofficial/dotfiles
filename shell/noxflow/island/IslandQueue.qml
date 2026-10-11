import QtQuick
import "../HoverEngagement.js" as HoverEngagement
import "IslandRoutes.js" as Routes

// IslandQueue.qml — turns submitted activities into island state.
//
// Extracted from IslandHost.qml. The host had the activity descriptors, the
// display/deactivate transitions, the deferred-replay logic and the hide timer
// all in one block, mixed with the view.
//
// The fix for the "no OSD after closing quick settings" stall lives here: an
// activity that arrives while a panel owns the screen is deferred, not
// dropped. The previous code returned early without finishing or displaying
// it, so the controller still owned it and suppressed the next one too.



QtObject {
    id: root

    // ── Inputs ──
    property var activityController: null
    property string activityDetail: ""

    /// True while a major panel owns the screen.
    property bool panelOpen: false

    /// Emitted after the queue has retired an activity and the host's mirrored
    /// state is consistent again.
    ///
    /// Two `property var` callbacks used to sit here — `display` and
    /// `deactivate`. Nothing assigned or read either one after the split moved
    /// the calls into IslandQueueHost's `show()`/`stop()` API, so both were
    /// dead.
    ///
    /// This was a `property var onSettled` callback. As a property it was
    /// assigned a binding in IslandQueueHost, and a binding tracks every
    /// property its body reads — including `guardVolume`, which the host's
    /// seedGuards() writes. As soon as seedGuards started writing a guard that
    /// the body had already read, the binding was writing its own dependency
    /// and Qt reported "Binding loop detected for property onSettled" on every
    /// load. A signal has no dependency tracking, which is what a callback that
    /// deliberately mutates host state needs to be.
    signal settled()

    // ── State the host mirrors ──
    property string currentKind: "idle"
    property int currentPriority: 0
    property double currentStarted: 0
    property string currentActivityId: ""

    property string activityLabel: ""
    property string activityIcon: ""
    property real activityValue: 0
    property real activityMaximum: 100
    property bool expanded: false

    // Held while a panel owns the screen, replayed once the panel closes.
    property var deferredActivity: null

    property Timer hideTimer: Timer {
        interval: 2000
        repeat: false
        onTriggered: root.retire()
    }

    // Kinds that expand the card rather than showing a compact pill.
    function shouldExpand(kind) {
        return ["media", "notification", "timer"].indexOf(kind) >= 0;
    }

    /// Hand an activity to the controller.
    function enqueue(kind, label, icon, value, maximum, priority, timeout) {
        root.activityController.submitActivity({
            id: kind + "::" + label + "::" + Date.now(),
            kind: kind,
            severity: HoverEngagement.CRITICAL_KINDS.indexOf(kind) >= 0 ? "critical" : "info",
            priority: priority,
            title: label,
            detail: root.activityDetail,
            value: value,
            maximum: maximum,
            timeoutMs: timeout,
            targetPanel: Routes.panel(kind) || "",
            targetSection: Routes.section(kind) || "",
            monitor: ""
        });
    }

    /// Show an activity. The controller hands one over via activityReady.
    function show(entry) {
        if (root.panelOpen) {
            // Defer rather than drop: repro was "open quick settings, change
            // the volume, close the panel, then change brightness" and the
            // second OSD never appeared.
            root.deferredActivity = entry;
            return;
        }
        root.deferredActivity = null;
        root.currentActivityId = entry.id || "";
        root.currentKind = entry.kind;
        root.currentPriority = entry.priority;
        root.currentStarted = Date.now();
        root.activityLabel = entry.title || entry.label || entry.kind;
        root.activityIcon = entry.icon || Routes.icon(entry.kind);
        root.activityValue = Math.max(0, entry.value);
        root.activityMaximum = Math.max(1, entry.maximum);
        root.expanded = root.shouldExpand(entry.kind);
        root.hideTimer.stop();
        root.hideTimer.interval = entry.timeoutMs || entry.timeout || 2000;
        root.hideTimer.restart();
    }

    /// Replay an activity that was suppressed while a panel was open.
    function flushDeferred() {
        if (!root.deferredActivity || root.panelOpen) return;
        var entry = root.deferredActivity;
        root.deferredActivity = null;
        if (!entry || !entry.id) return;
        var current = root.activityController.activeActivity;
        if (current && current.id === entry.id) {
            // The controller still owns it: show it now and restart its timer.
            root.show(entry);
        } else {
            // A newer activity already replaced it; this one is stale.
            root.activityController.finishActivity(entry.id);
        }
    }

    /// The hide timer fired.
    function retire() {
        root.expanded = false;
        var finishedId = root.currentActivityId;
        root.currentActivityId = "";
        root.currentKind = "idle";
        root.currentPriority = 0;
        root.currentStarted = 0;
        root.activityController.finishActivity(finishedId);
        root.settled();
    }

    /// An explicit deactivate (pin taken over, Escape, state reset).
    function stop() {
        root.hideTimer.stop();
        root.retire();
    }
}
