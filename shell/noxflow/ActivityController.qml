import QtQuick
import Quickshell
import "ActivityArbitration.js" as Arbitration

QtObject {
    id: root

    readonly property int hoverDwellMs: 140
    readonly property int transitGraceMs: 450
    property var state: Arbitration.newState()
    property var hosts: ({})
    property var pendingRoute: null
    property var lastEventKeys: ({})

    readonly property string mode: state.mode
    readonly property string targetMonitor: state.targetMonitor
    readonly property var activeActivity: state.activity
    readonly property var activeDashboard: state.pin || state.dashboard
    readonly property bool dashboardPinned: state.pin !== null

    signal dashboardActivated(string monitor, string kind)
    signal dashboardDismissed(string monitor)
    signal activityReady(string monitor, var activity)
    signal layerChanged(string monitor, string mode)

    function monitorName(screen) { return screen && screen.name ? String(screen.name) : ""; }
    function focusedMonitor() {
        return Quickshell.activeScreen && Quickshell.activeScreen.name
            ? String(Quickshell.activeScreen.name) : (root.targetMonitor || Object.keys(root.hosts)[0] || "");
    }
    function registerHost(screen, host) {
        var name = monitorName(screen);
        if (!name || !host) return;
        var next = {};
        for (var key in hosts) next[key] = hosts[key];
        next[name] = host;
        hosts = next;
    }
    function unregisterHost(screen) {
        var name = monitorName(screen);
        var next = {};
        for (var key in hosts) if (key !== name) next[key] = hosts[key];
        hosts = next;
    }
    function routeFor(monitor, kind, originGeometry, targetPanel, targetSection) {
        return {
            monitor: monitor || focusedMonitor(), kind: kind,
            originGeometry: originGeometry || Qt.rect(0, 0, 0, 0),
            targetPanel: targetPanel || "", targetSection: targetSection || ""
        };
    }
    function sourceHoverChanged(monitor, kind, hovered, originGeometry, targetPanel, targetSection) {
        var route = routeFor(monitor, kind, originGeometry, targetPanel, targetSection);
        if (hovered) {
            pendingRoute = route;
            hoverDwell.restart();
            return;
        }
        if (pendingRoute && pendingRoute.monitor === route.monitor && pendingRoute.kind === route.kind) {
            pendingRoute = null;
            hoverDwell.stop();
            return;
        }
        if (activeDashboard && activeDashboard.monitor === route.monitor && activeDashboard.kind === route.kind && !dashboardPinned)
            transitGrace.restart();
    }
    function activatePendingDashboard() {
        if (!pendingRoute) return;
        var route = pendingRoute;
        pendingRoute = null;
        state = Arbitration.showDashboard(state, route);
        dashboardActivated(route.monitor, route.kind);
    }
    function holdDashboard() { transitGrace.stop(); }
    function leaveDashboard() { if (!dashboardPinned) transitGrace.restart(); }
    function pin(route) {
        transitGrace.stop();
        state = Arbitration.pinDashboard(state, route);
        dashboardActivated(state.targetMonitor, route.kind);
    }
    function unpin() {
        var monitor = state.targetMonitor;
        state = Arbitration.unpinDashboard(state);
        dashboardDismissed(monitor);
    }
    function dismissDashboard() {
        var monitor = state.targetMonitor;
        state = Arbitration.dismissDashboard(state);
        dashboardDismissed(monitor);
    }
    function openLayer(mode, monitor) {
        state = Arbitration.openLayer(state, mode, monitor || focusedMonitor());
        layerChanged(state.targetMonitor, mode);
    }
    function closeLayer() {
        var monitor = state.targetMonitor;
        state = Arbitration.closeLayer(state);
        layerChanged(monitor, state.mode);
    }
    function submitActivity(activity) {
        var normalized = Arbitration.normalizeActivity(activity, focusedMonitor());
        var key = normalized.kind + "::" + normalized.title;
        var now = Date.now();
        if (lastEventKeys[key] && now - lastEventKeys[key] < 300) return false;
        var keys = {};
        for (var old in lastEventKeys) keys[old] = lastEventKeys[old];
        keys[key] = now;
        lastEventKeys = keys;
        var previousId = state.activity ? state.activity.id : "";
        state = Arbitration.enqueue(state, normalized, normalized.monitor);
        if (state.activity && state.activity.id !== previousId)
            activityReady(state.targetMonitor, state.activity);
        return true;
    }
    function finishActivity(id) {
        var previousId = state.activity ? state.activity.id : "";
        state = Arbitration.finishActivity(state, id || previousId);
        if (state.activity && state.activity.id !== previousId)
            activityReady(state.targetMonitor, state.activity);
        else if (state.mode === "dashboard" && activeDashboard)
            dashboardActivated(state.targetMonitor, activeDashboard.kind);
    }
    function handleEscape() {
        var previous = Arbitration.view(state);
        state = Arbitration.escape(state);
        if (previous.mode === "launcher" || previous.mode === "calendar") layerChanged(previous.targetMonitor, state.mode);
        else if (previous.pin || previous.dashboard) dashboardDismissed(previous.targetMonitor);
    }

    property Timer hoverDwell: Timer {
        interval: root.hoverDwellMs
        repeat: false
        onTriggered: root.activatePendingDashboard()
    }
    property Timer transitGrace: Timer {
        interval: root.transitGraceMs
        repeat: false
        onTriggered: root.dismissDashboard()
    }
}
