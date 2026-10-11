import QtQuick
import "IslandRoutes.js" as Routes

// IslandPanelYield.qml — the island's relationship with the panel coordinator.
//
// Decision 8: only one panel is open at a time, and the coordinator owns that.
// This component is the island's single point of contact with it. It tracks
// whether a major panel currently owns the screen, retires a pin whose reason
// for existing has gone, and replays any OSD that was suppressed while the
// panel was up.
//
// The "no OSD after closing quick settings" stall lived here: an activity that
// arrived while a panel owned the screen was returned early without being
// finished or displayed, so the controller still owned it and suppressed the
// next one too. Replay lives in IslandQueue.flushDeferred() and is called from
// here the moment the panel closes.

Item {
    id: root

    // ── Inputs ──
    required property var host            // IslandHost.qml
    required property var router          // IslandRouter.qml

    /// True while a major panel owns the screen.
    property bool panelOpen: false
    property bool launcherVisible: false

    // ── Callbacks into the host ──
    property var notifyPanelClosed: null
    property var flushDeferred: null
    property var geometry: null

    /// Name of the panel currently open, for pin bookkeeping.
    readonly property string activePanelName:
        shellRoot && shellRoot.coordinator ? shellRoot.coordinator.activePanel : ""

    // ── Panel routing ──
    // Panel routing lives in island/IslandRoutes.js and island/IslandRouter.qml.
    // It used to be a switch statement on the host listing twenty kinds,
    // including "sync" (whose only producer was the sync pill, removed in
    // phase 2) and an "updater" panel that no component provides.
    function openPanelForKind(kind) {
        root.router.kind = kind;
        root.router.open();
    }

    /// The island's open/close action. From idle the clock opens the unified
    /// Control Centre; from a dashboard kind it opens that kind's panel.
    function openPanelFromIsland() {
        if (root.launcherVisible) return;
        if (root.host.islandState === "idle") {
            shellRoot.coordinator.toggle("quick-settings", root.monitorName, root.geometry);
            return;
        }
        root.router.open();
    }

    property string monitorName: root.host && root.host.screen && root.host.screen.name
        ? root.host.screen.name : ""

    // ── Coordinator events ──
    Connections {
        target: shellRoot.coordinator
        function onActivePanelChanged() {
            var wasOpen = root.panelOpen;
            var nowOpen = shellRoot.coordinator.activePanel !== "";
            root.panelOpen = nowOpen;
            root.host.panelOpen = nowOpen;
            // If the major panel that was opened in tandem with the current pin
            // has now closed, retire the pin so it does not outlive its reason
            // for existing.
            if (wasOpen && !nowOpen && root.notifyPanelClosed)
                root.notifyPanelClosed(shellRoot.coordinator.previousPanel);
            // Replay any OSD that was suppressed while the panel owned the
            // screen.
            if (!nowOpen && root.flushDeferred) Qt.callLater(root.flushDeferred);
        }
        function onPanelChanged(panel, previous) {
            if (panel === "" && previous !== "" && root.notifyPanelClosed)
                root.notifyPanelClosed(previous);
        }
    }
}