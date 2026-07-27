import QtQml
import "ModelUtils.js" as Utils

ProviderModel {
    providerName: "hyprland"
    property var workspaces: []
    property var windows: []
    property var monitors: []
    property var activeWorkspace: null
    property var urgentWindows: []
    property var specialWorkspaces: []

    function applySnapshot(snapshot) {
        if (!Utils.applyBase(this, snapshot, providerName)) return false;
        var next = snapshot.data;
        workspaces = Array.isArray(next.workspaces) ? next.workspaces : [];
        windows = Array.isArray(next.windows) ? next.windows : [];
        monitors = Array.isArray(next.monitors) ? next.monitors : [];
        activeWorkspace = next.active_workspace === undefined ? null : next.active_workspace;
        urgentWindows = Array.isArray(next.urgent_windows) ? next.urgent_windows : [];
        specialWorkspaces = Array.isArray(next.special_workspaces) ? next.special_workspaces : [];
        return true;
    }
}
