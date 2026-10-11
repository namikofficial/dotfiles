import QtQuick
import Quickshell
import Quickshell.Io
import "WorkspaceModel.js" as WorkspaceModel
import "../WorkspacePresentation.js" as Presentation
import "../components" as Components

// WorkspaceState.qml — the bar's workspace bindings, as one QObject.
//
// Bar.qml used to carry ~70 lines of workspace derivation inline. Splitting it
// out keeps Bar.qml to layout, and makes the workspace rules testable without
// instantiating the whole bar.
//
// The derivation itself is WorkspaceModel.js. This object only binds it to a
// live HyprlandModel and owns the optimistic-pending dispatch.



QtObject {
    id: root

    required property var hyprland
    required property string monitorName

    // Set while a dispatch is in flight, so the pill highlights immediately
    // instead of waiting for the compositor to confirm.
    property string pendingWorkspace: ""

    readonly property var monitor: WorkspaceModel.findMonitor(hyprland.monitors, monitorName)

    readonly property string activeWorkspace:
        WorkspaceModel.activeWorkspace(hyprland, monitor, monitorName, pendingWorkspace)

    // Signature of the current entry list. Only reassigned `entries` when the
    // list actually changed, so a Repeater is not rebuilt on every snapshot.
    property var entries: []
    property string entriesSignature: ""

    function refresh() {
        var next = WorkspaceModel.build(hyprland, monitorName, activeWorkspace);
        var signature = next.join(",");
        if (signature === entriesSignature) return;
        entriesSignature = signature;
        entries = next;
    }

    /// Per-workspace view state, consumed by WorkspaceCluster.
    function presentation(name) {
        var isActive = name === activeWorkspace;
        var hasWindow = isActive && Presentation.activeWindowMatches(
            name, monitorName, hyprland.focusedMonitor,
            hyprland.activeWorkspace, hyprland.activeWindow);
        return {
            active: isActive,
            occupied: WorkspaceModel.occupied(hyprland, name, monitorName),
            urgent: WorkspaceModel.urgent(hyprland, name, monitorName),
            hasActiveWindow: hasWindow,
            activeApp: hasWindow ? Presentation.applicationName(hyprland.activeWindow) : "",
            activeTitle: hasWindow ? Presentation.windowTitle(hyprland.activeWindow) : ""
        };
    }

    readonly property int urgentCount: WorkspaceModel.urgentCount(hyprland, monitorName)

    /// Clear the optimistic selection once hyprland confirms it, or after a
    /// grace period if it never does.
    function confirmPending() {
        if (pendingWorkspace !== ""
            && WorkspaceModel.workspaceId(hyprland.activeWorkspace) === pendingWorkspace) {
            pendingWorkspace = "";
            pendingClearTimer.stop();
        }
        refresh();
    }

    property Components.Command dispatch: Components.Command {
        label: "Workspace switch"
        onExited: function (code) {
            if (code === 0) root.pendingClearTimer.restart();
            else root.pendingWorkspace = "";
        }
    }
    property Timer pendingClearTimer: Timer {
        interval: 1200
        onTriggered: root.pendingWorkspace = ""
    }

    function focus(name) {
        // The target is interpolated into a `hyprctl eval` argument, so it is
        // validated before it becomes a command.
        if (!WorkspaceModel.isValidTarget(name)) return;
        pendingWorkspace = String(name);
        refresh();
        dispatch.run(["hyprctl", "eval", WorkspaceModel.dispatchArgument(pendingWorkspace)]);
    }

    function cycle(direction) {
        dispatch.run(["hyprctl", "eval",
            WorkspaceModel.dispatchArgument(direction < 0 ? "e-1" : "e+1")]);
    }
}