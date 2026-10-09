import QtQuick
import Quickshell
import Quickshell.Io
import "../theme" as Theme
import "../HoverEngagement.js" as HoverEngagement
import "IslandRoutes.js" as Routes
import "." as Local

// IslandHost.qml — the island's state machine. Was NoxIsland.qml, 1146 lines
// holding the view, the queue, the hover-and-pin machine, the panel routing
// and the timers; Phase 3 split it into the island/ components, leaving this
// file owning state and nothing else.
//
// Decision 7: a kind exists only together with a producer. Eight entry points
// had no caller anywhere in the shell and were removed.

Item {
    id: root
    property var screen
    required property var noxd
    required property var audio
    required property var brightness
    required property var hyprland
    required property var calModel
    required property var launcherComponent
    required property var battery
    required property var network
    required property var bluetooth
    required property var media
    required property var notificationModel
    required property var systemModel
    required property var updates
    required property var activityController

    // ── State machine ──
    // Decision 7: the island's live kinds now come from IslandRoutes.js rather
    // than a local `states` array. The old array named six kinds — recording,
    // file-transfer, ai-completion, build-result, mic, network-warning — that
    // no producer in the shell could ever produce.
    property string islandState: "idle"
    property alias inputRegionItem: islandCard
    property bool expanded: false
    property bool hoverExpanded: false

    // ── Hover-and-pin state ──
    // IslandEngagement.qml owns the machine and mirrors it back here; see
    // HoverEngagement.js for the pure transitions and generation guards.
    property var engagement: HoverEngagement.newState()
    property int transitGraceMs: Theme.Tokens.islandTransitGrace

    // ── Panel yield ──
    property bool panelOpen: false
    property bool calendarExpanded: false
    // Keep the inline calendar in the top-chrome input mask while it is
    // available, so its close button receives pointer events.
    property alias calendarInputRegionItem: layers.calendarHostItem
    property bool launcherOpen: false
    property bool launcherClosing: false
    property bool launcherWasVisible: false
    readonly property bool launcherVisible: launcherOpen || launcherClosing

    // ── Derived state ──
    // IslandState.qml owns only what can be derived from a source object:
    // active window text, dashboard visibility from the route table and the
    // geometry clamps. The host owns the mutable state; pushing copies of it
    // into IslandState made those properties write-only.
    Local.IslandState {
        id: state
        screen: root.screen
        hyprland: root.hyprland
        audio: root.audio
        brightness: root.brightness
        activityController: root.activityController

        islandState: root.islandState
    }

    readonly property bool visualExpanded: expanded || hoverExpanded
    readonly property bool dashboardVisible: state.dashboardVisible
    readonly property bool reducedMotion: Theme.Tokens.reducedMotion
    property date now: new Date()
    readonly property bool hoverEngaged: engagementState.hoverEngaged
    readonly property string activeWin: state.activeWin
    readonly property string activeApp: state.activeApp

    // ── Activity state ──
    property string activityLabel: ""
    property string activityIcon: ""
    property string activityDetail: ""
    property real activityValue: 0
    property real activityMaximum: 100
    readonly property int displayPercent:
        Math.round(activityMaximum > 0 ? (activityValue / activityMaximum * 100) : activityValue)

    // The shell-level ActivityController owns arbitration and queueing. The
    // host keeps only the activity it is currently rendering.
    property string currentKind: "idle"
    property int currentPriority: 0
    property double currentStarted: 0
    property string currentActivityId: ""

    // Timer OSD. IslandTimers owns the countdown and writes the label only
    // while currentKind === "timer" (Phase 1 item 1.11: the tick must not
    // overwrite another OSD). These are mirrors for the card and the shell.
    property int timerTotalSeconds: 0
    readonly property int timerRemainingSeconds: producers.timerRemainingSeconds
    readonly property bool timerActive: producers.timerActive

    // Dashboard one-shot status line.
    property bool dashboardStatusVisible: false
    property string dashboardStatusText: ""
    property real dashboardStatusValue: 0
    property real dashboardStatusMaximum: 1

    // Priority of the timer OSD. Every other priority lives with its producer:
    // IslandEvents owns the audio/media/battery ones, because a priority with
    // no producer is exactly the dead kind decision 7 removed.
    readonly property int priTimer: 9

    readonly property real launcherHeight: state.launcherHeight
    readonly property real calendarHeight: state.calendarHeight
    readonly property real pillW: Theme.Tokens.scaled(Theme.Tokens.islandIdleWidth)
    readonly property real expandW: state.expandW

    // The island's height in its layer-shell window. TopChrome sizes itself to
    // `Math.max(heightToolbar, island.implicitHeight)`, so this binding is the
    // only thing that makes room for the dashboard, calendar and launcher. The
    // Phase 3 split dropped it; see NOXFLOW_REPAIR_PLAN.md 0.5, defect 5.
    implicitHeight: launcherVisible ? root.launcherHeight
        : calendarExpanded ? root.calendarHeight
        : dashboardVisible ? Math.min(screen ? screen.height - Theme.Tokens.scaled(Theme.Tokens.heightToolbar + 24) : Theme.Tokens.scaled(520), Theme.Tokens.scaled(520))
        : visualExpanded ? Theme.Tokens.scaled(76)
        : Theme.Tokens.scaled(Theme.Tokens.islandIdleHeight)

    Behavior on implicitHeight { enabled: !root.reducedMotion; NumberAnimation { duration: Theme.Tokens.islandExpandDuration; easing.type: Easing.OutCubic } }

    focus: launcherVisible || islandPinned || root.engagement.critical.active
        || root.engagement.osd.active || root.calendarExpanded || root.hoverEngaged
    activeFocusOnTab: true
    // Return and Space did the same thing; one handler serves both so the two
    // cannot drift apart.
    function activateFromKeyboard() {
        if (root.launcherVisible || root.calendarExpanded) return false;
        if (root.islandState === "idle") root.openInlineCalendar();
        else if (!root.dashboardVisible) root.openPanelFromIsland();
        return true;
    }
    Keys.onReturnPressed: function(event) {
        if (root.activateFromKeyboard()) event.accepted = true;
    }
    Keys.onSpacePressed: function(event) {
        if (root.activateFromKeyboard()) event.accepted = true;
    }
    // Decision 6: Escape closes whichever layer is active, outermost first.
    Keys.onEscapePressed: function(event) {
        if (engagementState.handleEscape()) event.accepted = true;
    }

    Component.onCompleted: {
        islandState = "idle";
        currentKind = "idle";
        producers.seedGuards();
    }

    // ── Queue ──
    // IslandQueue.qml owns the activity lifecycle (submit, show, defer, retire)
    // and IslandQueueHost.qml owns the forwarding between it and this state
    // machine. The fix for the "no OSD after closing quick settings" stall lives
    // in the queue: an activity that arrives while a panel owns the screen is
    // deferred, not dropped.
    Local.IslandQueueHost {
        id: queue
        root: root
        clearTimer: function () { producers.clearTimer() }
        afterSettled: function () { root.afterActivitySettled() }
    }

    function enqueue(kind, label, icon, value, maximum, priority, timeout) {
        queue.enqueue(kind, label, icon, value, maximum, priority, timeout);
    }
    function display(entry) { queue.show(entry) }
    function deactivate() {
        queue.stop();
        if (currentKind === "timer") producers.clearTimer();
        engagementState.onActivityFinished();
        root.restoreEngagementContext();
        producers.seedGuards();
    }
    function flushDeferredActivity() { queue.flushDeferred() }

    function afterActivitySettled() {
        engagementState.onActivityFinished();
        root.restoreEngagementContext();
        producers.seedGuards();
    }

    // ── Panel routing and yield ──
    // IslandRouter.qml routes a kind to its panel (via IslandRoutes.js);
    // IslandPanelYield.qml is the island's single point of contact with the
    // panel coordinator, which owns the "one panel at a time" rule.
    Local.IslandRouter {
        id: router
        kind: root.islandState
        monitorName: root.screen && root.screen.name ? root.screen.name : ""
        geometry: root.islandGeometry()
        externalAction: producers.runSystemUpdate
    }

    Local.IslandPanelYield {
        id: panelYield
        host: root
        router: router
        geometry: root.islandGeometry()
        launcherVisible: root.launcherVisible
        notifyPanelClosed: function (panelName) { root.notifyPanelClosed(panelName) }
        flushDeferred: function () { root.flushDeferredActivity() }
    }

    function openPanelForKind(kind) { panelYield.openPanelForKind(kind) }
    function openPanelFromIsland() { panelYield.openPanelFromIsland() }

    function closeInlineCalendar() { layers.closeCalendar() }
    function openInlineCalendar() { layers.openCalendar() }

    // ── Source hover / pin engagement ──
    // Extracted to island/IslandEngagement.qml. The pure transitions already
    // lived in HoverEngagement.js; what remained here was the imperative shell
    // (timers, the ActivityController round trip, and the pointer grace timer)
    // mixed into the view. This file now only feeds it events and re-exports
    // its state.
    Local.IslandEngagement {
        id: engagementState
        host: root
        activityController: root.activityController
        monitorName: root.screen && root.screen.name ? root.screen.name : ""
        transitGraceMs: root.transitGraceMs

        // ── Inputs: host -> machine ──
        // Only properties the machine reads are bound down to it.
        currentKind: root.currentKind
        panelOpen: root.panelOpen
        launcherVisible: root.launcherVisible
        calendarExpanded: root.calendarExpanded

        // ── Outputs: machine -> host ──
        // The machine *writes* islandState, hoverExpanded and engagement. Bound
        // down instead, every write was swallowed and `enterOsd` never
        // expanded the island. Same direction mistake as the queue's show().
        onIslandStateChanged: root.islandState = engagementState.islandState
        onHoverExpandedChanged: root.hoverExpanded = engagementState.hoverExpanded
        onEngagementChanged: root.engagement = engagementState.engagement
    }

    readonly property bool islandPinned: engagementState.pinned

    // Called by bar capsules when they are hovered and want to show their
    // dashboard in the island. Each source's hover state is tracked
    // independently so the user can move the pointer between chips without
    // losing the island context.
    //
    // These are one-line delegations to IslandEngagement, which owns the
    // machine. The host only re-exports them so TopChrome, the bar and
    // IslandCardHost have a stable surface to talk to.
    function sourceHoverChanged(kind, hovered, item) { engagementState.sourceHoverChanged(kind, hovered, item) }
    function cardHoverEntered() { engagementState.cardHoverEntered() }
    function cardHoverLeft() { engagementState.cardHoverLeft() }
    function pinToggle() { engagementState.pinToggle() }
    function pinRelease() { engagementState.pinRelease() }
    function armTransitTimer() { engagementState.armTransitTimer() }
    function maybeRetireAfterPinRelease() { engagementState.maybeRetireAfterPinRelease() }
    function restoreEngagementContext() { engagementState.restoreEngagementContext() }

    function clickAwayCheck(point) {
        if (!engagementState.pinned) return;
        var cardPoint = islandCard.mapToItem(root, 0, 0);
        engagementState.clickAwayCheck(point, {
            x: cardPoint.x, y: cardPoint.y,
            width: islandCard.width, height: islandCard.height
        });
    }

    function notifyPanelClosed(panelName) {
        engagementState.notifyPanelClosed(panelName, panelYield.activePanelName);
    }

    function dashboardClosed() {
        if (engagementState.pinned) engagementState.pinRelease();
        root.engagement = HoverEngagement.clearSourceHover(root.engagement);
        root.activityController.dismissDashboard();
    }

    // ── Daemon events, clocks ──
    // island/IslandProducers.qml hosts IslandEvents and IslandTimers. Both
    // already coupled to the host by callback, so hosting them there added no
    // new state boundary and brought the host back under the 350-line cap.
    Local.IslandProducers {
        id: producers
        host: root
    }

    // ── Calendar + launcher layers ──
    // Extracted to island/IslandLayers.qml. Both are overlays hosted in the
    // island's slot with a shared open/close lifecycle and an Escape rule.
    Local.IslandLayers {
        id: layers
        host: root
        anchors.fill: parent
        screen: root.screen
        noxd: root.noxd
        calModel: root.calModel
        launcherComponent: root.launcherComponent
        activityController: root.activityController
        calendarHeight: root.calendarHeight

        // ── Outputs: layers -> host ──
        // IslandLayers owns and assigns these four. They were bound down
        // instead, so every write stopped at the layer: the calendar never
        // expanded and `launcherVisible` never went true. Plan 0.5, defect 4.
        onCalendarExpandedChanged: root.calendarExpanded = layers.calendarExpanded
        onLauncherOpenChanged: root.launcherOpen = layers.launcherOpen
        onLauncherClosingChanged: root.launcherClosing = layers.launcherClosing
        onLauncherWasVisibleChanged: root.launcherWasVisible = layers.launcherWasVisible

        onFocusRequested: root.forceActiveFocus()
    }

    // ── Island card ──
    // The card's visual tree is island/IslandCard.qml, its dashboard bodies are
    // island/bodies/, and IslandCardHost.qml owns the property forwarding
    // between this state machine and that view. This host owns state only.
    Local.IslandCardHost {
        id: islandCard
        root: root
        visible: !root.calendarExpanded
    }

    // ── Launcher control ──
    function openLauncher() { layers.openLauncher() }
    function closeLauncher() { layers.closeLauncher() }
    function toggleLauncher() { layers.toggleLauncher() }

    function islandGeometry() {
        var p = islandCard.mapToItem(null, 0, 0);
        return Qt.rect(p.x, p.y, islandCard.width, islandCard.height);
    }

    // ── Public helpers ──
    function formatTime(s) { return producers.formatTime(s) }
    function startTimer(s) { return producers.startTimer(s) }
}
