import QtQml
import "ModelUtils.js" as Utils

ProviderModel {
    providerName: "hyprland"
    property var workspaces: []
    property var windows: []
    property var monitors: []
    property var activeWorkspace: null
    property var activeWindow: null
    property string focusedMonitor: ""
    property var urgentWindows: []
    property var specialWorkspaces: []
    readonly property string activeWorkspaceName: workspaceName(activeWorkspace)
    readonly property string activeWindowAddress: activeWindow && activeWindow.address ? String(activeWindow.address) : ""
    readonly property string activeWindowApp: applicationName(activeWindow)
    readonly property string activeWindowTitle: activeWindow && activeWindow.title ? String(activeWindow.title).trim() : ""
    readonly property string activeWindowLabel: activeWindowTitle || activeWindowApp

    function workspaceName(workspace) {
        if (!workspace) return "";
        if (typeof workspace !== "object") return String(workspace);
        if (workspace.name !== undefined && workspace.name !== null && String(workspace.name) !== "") return String(workspace.name);
        return workspace.id === undefined || workspace.id === null ? "" : String(workspace.id);
    }

    function applicationName(window) {
        if (!window || typeof window !== "object") return "";
        var raw = String(window.application_id || window.class || window.appid || window.initialClass || "").trim();
        if (!raw) return "";
        var pieces = raw.split(".");
        var label = pieces[pieces.length - 1].replace(/[-_]+/g, " ").trim();
        return label ? label.charAt(0).toUpperCase() + label.slice(1) : raw;
    }

    function applySnapshot(snapshot) {
        if (!Utils.applyBase(this, snapshot, providerName)) return false;
        var next = snapshot.data;
        workspaces = Array.isArray(next.workspaces) ? next.workspaces : [];
        windows = Array.isArray(next.windows) ? next.windows : [];
        monitors = Array.isArray(next.monitors) ? next.monitors : [];
        focusedMonitor = next.focused_monitor === undefined ? "" : String(next.focused_monitor);
        activeWorkspace = next.active_workspace === undefined ? null : next.active_workspace;
        activeWindow = next.active_window === undefined ? null : next.active_window;
        urgentWindows = Array.isArray(next.urgent_windows) ? next.urgent_windows : [];
        specialWorkspaces = Array.isArray(next.special_workspaces) ? next.special_workspaces : [];
        return true;
    }
}
