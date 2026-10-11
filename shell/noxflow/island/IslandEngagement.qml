import QtQuick
import "../HoverEngagement.js" as HoverEngagement
import "IslandRoutes.js" as Routes

// IslandEngagement.qml — the island's hover-and-pin state machine.
//
// Extracted from IslandHost.qml, which had grown to ~200 lines of engagement
// logic interleaved with the view and the queue. All of the pure state
// transitions already lived in HoverEngagement.js; this component is the
// imperative shell around them — timers, the ActivityController round trip,
// and the transitions that touch the host's `islandState`.
//
// The rules it enforces:
//   • A bar capsule hover adopts the island's context; moving between chips
//     does not lose it (each source is tracked independently).
//   • Pinning keeps a dashboard open until explicitly released.
//   • Click-away ignores the pinned source's own chip — pressing that chip
//     again is how you unpin.
//   • The pointer grace timer retires the island only when nothing claims it,
//     and only when no generation-stale callback can fire.



// An Item rather than a QtObject: this component owns Connections children,
// and a QtObject has no default property to assign them to. It draws nothing.
Item {
    id: root

    // ── Inputs ──
    property var host: null              // IslandHost.qml
    property var activityController: null
    property string monitorName: ""
    property int transitGraceMs: 450

    // ── State the host reads ──
    property var engagement: HoverEngagement.newState()
    property string islandState: "idle"
    property bool hoverExpanded: false
    property bool panelOpen: false
    property bool launcherVisible: false
    property bool calendarExpanded: false
    property string currentKind: "idle"

    property bool pinned: engagement.pin.active
    readonly property bool hoverEngaged: HoverEngagement.isEngaged(engagement)
    readonly property string effectiveKind: HoverEngagement.effectiveKind(engagement)
    readonly property bool criticalActive: engagement.critical.active
    readonly property bool osdActive: engagement.osd.active

    property var activeTransitToken: ({ generation: -1, deadline: 0 })

    function geometry() {
        return root.host && typeof root.host.islandGeometry === "function"
            ? root.host.islandGeometry() : Qt.rect(0, 0, 0, 0);
    }

    function panelFor(kind) {
        return { panel: Routes.panel(kind), section: Routes.section(kind) };
    }

    function sourceGeometry(sourceItem) {
        if (!sourceItem || typeof sourceItem.mapToItem !== "function") return root.geometry();
        var point = sourceItem.mapToItem(null, 0, 0);
        return Qt.rect(point.x, point.y, sourceItem.width || 0, sourceItem.height || 0);
    }

    // ── Source hover → island engagement ──
    // Each source's hover is tracked independently, so the pointer can move
    // from the workspace strip to the health capsule without the island
    // losing its context in between.
    function sourceHoverChanged(sourceKind, hovered, sourceItem) {
        if (HoverEngagement.SOURCE_KINDS.indexOf(sourceKind) < 0) return;
        var target = root.panelFor(sourceKind);
        root.activityController.sourceHoverChanged(
            root.monitorName, sourceKind, hovered, root.sourceGeometry(sourceItem),
            target.panel || "", target.section || "");
    }

    /// A bar capsule reported hover/leave.
    function adoptHoveredSource(sourceKind) {
        if (root.engagement.pin.active) return;      // pin wins
        if (root.engagement.critical.active) return;  // critical wins
        if (root.islandState === sourceKind) {
            root.hoverExpanded = true;
            return;
        }
        root.islandState = sourceKind;
        root.hoverExpanded = true;
        root.currentKind = "idle"; // suspend the OSD queue while hover-driven
    }

    /// The card itself reported hover.
    function cardHoverEntered() {
        root.activeTransitToken = { generation: root.engagement.generation, deadline: 0 };
        root.pointerGraceTimer.stop();
        if (root.islandState === "idle" && !root.engagement.pin.active && !root.engagement.critical.active)
            root.hoverExpanded = true;
    }

    function cardHoverLeft() {
        if (HoverEngagement.isAnySourceHovered(root.engagement)) return;
        if (root.engagement.pin.active) return;
        if (root.engagement.critical.active) return;
        if (root.engagement.osd.active) return;
        if (root.panelOpen || root.launcherVisible) return;
        root.armTransitTimer();
    }

    // ── Pin / unpin ──
    function pinToggle() {
        if (root.launcherVisible) return;
        if (root.calendarExpanded) return;
        if (root.engagement.critical.active) return;
        var target = root.effectiveKind || root.islandState;
        if (!target || target === "idle") return;
        var wasPinned = root.engagement.pin.active && root.engagement.pin.kind === target;
        root.engagement = HoverEngagement.togglePin(root.engagement, target);
        if (wasPinned) {
            root.activityController.unpin();
        } else {
            var panelTarget = root.panelFor(target);
            root.activityController.pin(root.activityController.routeFor(
                root.monitorName, target, root.geometry(),
                panelTarget.panel || "", panelTarget.section || ""));
        }
        root.activeTransitToken = { generation: root.engagement.generation, deadline: 0 };
        root.pointerGraceTimer.stop();
        if (root.engagement.pin.active) {
            root.islandState = root.engagement.pin.kind;
            root.hoverExpanded = true;
        } else {
            root.maybeRetireAfterPinRelease();
        }
    }

    function pinRelease() {
        if (!root.engagement.pin.active) return;
        root.engagement = HoverEngagement.releasePin(root.engagement);
        root.activityController.unpin();
        root.activeTransitToken = { generation: root.engagement.generation, deadline: 0 };
        root.pointerGraceTimer.stop();
        root.maybeRetireAfterPinRelease();
    }

    /// A tap landed in the top-chrome input region.
    function clickAwayCheck(point, islandBounds) {
        if (!root.engagement.pin.active) return;
        // The pinned source's own chip is NOT click-away: pressing the same
        // bar capsule again is how the user unpins. This used to pass an empty
        // array, so every tap — including one on the triggering chip — was
        // classified as click-away and silently dropped the pin.
        var sourceBounds = [];
        if (root.engagement.pin.kind && shellRoot.triggerRegistry) {
            var rect = shellRoot.triggerRegistry.trigger(root.engagement.pin.kind, root.monitorName);
            if (rect) {
                sourceBounds.push({
                    x: rect.globalX, y: rect.globalY,
                    width: rect.globalWidth, height: rect.globalHeight
                });
            }
        }
        if (HoverEngagement.isClickAway(root.engagement, sourceBounds, islandBounds, point))
            root.pinRelease();
    }

    function maybeRetireAfterPinRelease() {
        // Only retire when nothing else claims the island.
        if (HoverEngagement.isAnyHovered(root.engagement)) return;
        if (root.engagement.osd.active) return;
        if (root.engagement.critical.active) return;
        if (root.panelOpen) return;
        if (root.launcherVisible) return;
        root.islandState = "idle";
        root.hoverExpanded = false;
    }

    function notifyPanelClosed(panelName, activePanelName) {
        if (!root.engagement.pin.active) return;
        if (panelName && activePanelName && panelName !== activePanelName) return;
        root.pinRelease();
    }

    /// Escape: close the topmost layer, unpin, or drop a transient hover
    /// engagement. Named `handleEscape` because `escape` is a reserved QML
    /// method name ("Illegal method name" at parse time).
    function handleEscape() {
        var host = root.host;
        if (root.launcherVisible) { if (host) host.closeLauncher(); return true }
        if (root.calendarExpanded) { if (host) host.closeInlineCalendar(); return true }
        if (root.engagement.pin.active) { root.pinRelease(); return true }
        if (root.engagement.critical.active) return false;
        if (root.hoverEngaged) {
            root.engagement = HoverEngagement.clearSourceHover(root.engagement);
            root.activityController.dismissDashboard();
            root.activeTransitToken = { generation: root.engagement.generation, deadline: 0 };
            root.pointerGraceTimer.stop();
            root.maybeRetireAfterPinRelease();
            return true;
        }
        if (root.panelOpen) {
            var coord = shellRoot.coordinator;
            if (coord && coord.activePanel) coord.close(coord.activePanel);
            return true;
        }
        return false;
    }

    // ── Activities ──
    /// The host routes every ActivityController signal through here. These used
    /// to be a Connections block on the host, which meant the engagement machine
    /// and the events that drive it lived in different files.
    Connections {
        target: root.activityController
        function onDashboardActivated(monitor, kind) {
            if (monitor !== root.monitorName) return;
            root.host.engagement = HoverEngagement.recordSourceHover(root.host.engagement, kind, true);
            root.adoptHoveredSource(kind);
        }
        function onDashboardDismissed(monitor) {
            if (monitor !== root.monitorName) return;
            root.onActivityDismissed();
        }
        function onActivityReady(monitor, activity) {
            if (monitor !== root.monitorName) return;
            root.onActivityReady(activity);
            root.host.display(activity);
        }
    }

    function onActivityReady(activity) {
        if (root.engagement.pin.active && HoverEngagement.CRITICAL_KINDS.indexOf(activity.kind) < 0) {
            // A pinned dashboard stays; the activity becomes its status line.
            if (root.host) root.host.showDashboardStatus(activity);
            return;
        }
        if (HoverEngagement.CRITICAL_KINDS.indexOf(activity.kind) >= 0)
            root.engagement = HoverEngagement.enterCritical(root.engagement, activity.kind);
        else
            root.engagement = HoverEngagement.enterOsd(root.engagement, activity.kind, activity.timeoutMs);
        // The card paints from islandState, not from the engagement machine: a
        // routine OSD is a *non-expanded* pill showing an icon and a slim
        // progress bar (IslandCard's `!visualExpanded && islandState !== "idle"`
        // row), and `expanded` is only set for the kinds that open the card.
        // The pre-split NoxIsland.display() assigned `islandState = entry.kind`
        // itself; the split moved that function into IslandQueue, which owns
        // only the queue's own mirrors, and nothing set islandState on this
        // path. The activity then arrived with islandState still "idle" and no
        // card was ever painted.
        root.islandState = activity.kind;
    }

    function onActivityDismissed() {
        root.engagement = HoverEngagement.clearSourceHover(root.engagement);
        if (!root.engagement.pin.active && !root.engagement.critical.active && !root.engagement.osd.active) {
            root.islandState = "idle";
            root.hoverExpanded = false;
        }
    }

    /// The OSD finished or was superseded.
    function onActivityFinished() {
        if (root.engagement.critical.active)
            root.engagement = HoverEngagement.exitCritical(root.engagement);
        if (root.engagement.osd.active)
            root.engagement = HoverEngagement.exitOsd(root.engagement);
        root.restoreEngagementContext();
    }

    function restoreEngagementContext() {
        var restored = HoverEngagement.effectiveKind(root.engagement);
        if (restored !== "") {
            root.islandState = restored;
            root.hoverExpanded = true;
            return;
        }
        root.islandState = "idle";
        root.hoverExpanded = false;
    }

    // ── Pointer grace ──
    function armTransitTimer() {
        root.activeTransitToken = HoverEngagement.armTransit(
            root.engagement, Date.now(), root.transitGraceMs);
        root.pointerGraceTimer.interval = root.transitGraceMs;
        root.pointerGraceTimer.restart();
    }

    property Timer pointerGraceTimer: Timer {
        id: pointerGraceTimer
        interval: root.transitGraceMs
        repeat: false
        onTriggered: {
            // Generation guard: a stale callback from a replaced engagement
            // must never close a newer one.
            if (!HoverEngagement.tickTransit(root.engagement, root.activeTransitToken, Date.now() + 1)) return;
            if (HoverEngagement.isAnyHovered(root.engagement)) return;
            if (root.engagement.pin.active) return;
            if (root.engagement.critical.active) return;
            if (root.engagement.osd.active) return;
            if (root.panelOpen) return;
            if (root.launcherVisible) return;
            // No engagement claims the island — drop it back to idle.
            if (root.islandState === "idle") { root.hoverExpanded = false; return }
            // A routine OSD sits on the idle queue; let its hide timer run.
            if (root.currentKind !== "idle") return;
            root.islandState = "idle";
            root.hoverExpanded = false;
        }
    }
}