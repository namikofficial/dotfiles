import QtQuick
import "." as Local

// IslandProducers.qml — the island's producers and its clocks.
//
// Two components that only ever *push into* the host and never hold state the
// host needs to read back through a bound-down property:
//
//   IslandEvents   daemon events and model signals -> island activities
//   IslandTimers   the 1 Hz clock, the dashboard-status timeout, startup guard
//
// They were instantiated inline in IslandHost.qml, which pushed that file past
// the plan's 350-line cap. Both already coupled to the host by *callback*
// (`enqueue`, `deactivate`, `clearDashboardStatus`), so hosting them together
// adds no new state-mirroring boundary — which is the whole risk here, since
// three sibling boundaries in this directory were wired backwards and silently
// disabled the island.
//
// The two values the host does read, `timerRemainingSeconds` and `timerActive`,
// flow child -> host, the direction that works.

Item {
    id: bridge

    required property var host            // IslandHost.qml

    // ── Inputs: host -> producers ──
    property var noxd: bridge.host.noxd
    property var audio: bridge.host.audio
    property var brightness: bridge.host.brightness
    property var media: bridge.host.media
    property var activityController: bridge.host.activityController

    // ── Outputs: producers -> host ──
    // IslandTimers owns the countdown; the host mirrors it for the card.
    readonly property int timerRemainingSeconds: timers.timerRemainingSeconds
    readonly property bool timerActive: timers.timerActive

    function seedGuards() { events.seedGuards() }
    function formatTime(s) { return timers.formatTime(s) }
    function startTimer(s) { timers.startTimer(s) }
    function deactivate() { timers.deactivate() }
    /// The host clears the timer OSD when the island retires from a timer card.
    /// IslandTimers owns `timerActive`, so this goes through here rather than
    /// the host assigning the mirror above, which is deliberately readonly.
    function clearTimer() { timers.timerActive = false }
    /// The update launcher the clock's one-shot runs.
    function runSystemUpdate() { return timers.runSystemUpdate() }

    // ── Producers ──
    Local.IslandEvents {
        id: events
        noxd: bridge.noxd
        audio: bridge.audio
        brightness: bridge.brightness
        media: bridge.media
        enqueue: bridge.host.enqueue
        deactivate: bridge.host.deactivate
    }

    // ── Clocks ──
    // Decision 9: the 1 Hz clock is the only timer that runs unconditionally —
    // everything else in the shell is event-driven.
    Local.IslandTimers {
        id: timers
        host: bridge.host
        activityController: bridge.activityController
        currentKind: bridge.host.currentKind
        deactivate: function () { bridge.host.deactivate() }
        endStartupSuppression: function () { events.seedGuards(); events.suppressStartupEvents = false }
        clearDashboardStatus: function () { bridge.host.dashboardStatusVisible = false }
    }
}