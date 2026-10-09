import QtQuick
import "." as Local

// IslandQueueHost.qml — binds IslandQueue to the host's state.
//
// The queue owns the activity lifecycle (submit, show, defer, retire). The host
// owns the properties that lifecycle writes. Connecting them was 30 lines of
// property forwarding inside IslandHost.qml; this wrapper holds it instead, so
// the host file describes the island rather than restating every binding.
//
// This is the same arrangement as IslandCardHost.qml: one place that forwards
// state between the island's state machine and its behaviour components, and no
// second copy of the state itself.
//
// ── Direction matters ────────────────────────────────────────────────────────
// The queue *writes* these properties (show() assigns currentKind, retire()
// clears them) and the host *reads* them, so the forward direction is
// queue -> host. This file originally bound them the other way round
// (`currentKind: wrapper.root.currentKind`), which made every write land on a
// bound property and vanish: after `queue.show()`, the host still reported
// currentKind "idle" and an empty label, so no OSD card was ever painted —
// volume, brightness and media alike. Only properties the queue genuinely
// *reads* are bound host -> queue.

Item {
    id: wrapper

    required property var root           // IslandHost.qml

    /// Clears the timer OSD when the island retires from a timer card.
    property var clearTimer: null

    // ── Behaviour ──
    // Settling a queue entry is not a binding: the callback writes back into
    // the engagement machine and re-seeds the OSD guards. A `settled` signal
    // rather than a bound `onSettled` property, because a binding tracks every
    // property its body reads and the callback rewrites several of them.
    property var afterSettled: null

    Local.IslandQueue {
        id: queue

        // Read-only inputs: the host owns these.
        activityController: wrapper.root.activityController
        activityDetail: wrapper.root.activityDetail
        panelOpen: wrapper.root.panelOpen

        // ── Outputs: queue -> host ──
        // The queue assigns these directly; mirror each change into the host
        // so the card and the shell see the activity that is on screen.
        onCurrentKindChanged: wrapper.root.currentKind = queue.currentKind
        onCurrentPriorityChanged: wrapper.root.currentPriority = queue.currentPriority
        onCurrentStartedChanged: wrapper.root.currentStarted = queue.currentStarted
        onCurrentActivityIdChanged: wrapper.root.currentActivityId = queue.currentActivityId
        onActivityLabelChanged: wrapper.root.activityLabel = queue.activityLabel
        onActivityIconChanged: wrapper.root.activityIcon = queue.activityIcon
        onActivityValueChanged: wrapper.root.activityValue = queue.activityValue
        onActivityMaximumChanged: wrapper.root.activityMaximum = queue.activityMaximum
        onExpandedChanged: wrapper.root.expanded = queue.expanded

        onSettled: if (wrapper.afterSettled) wrapper.afterSettled()
    }

    // ── API ──
    function enqueue(kind, label, icon, value, maximum, priority, timeout) {
        queue.enqueue(kind, label, icon, value, maximum, priority, timeout);
    }

    function show(entry) { queue.show(entry) }
    function stop() { queue.stop() }
    function flushDeferred() { queue.flushDeferred() }
}