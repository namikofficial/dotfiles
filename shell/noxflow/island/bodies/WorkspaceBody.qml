import QtQuick
import QtQuick.Layouts
import "../../theme" as Theme
import "." as Local

// WorkspaceBody.qml — island dashboard for the workspace strip.



ColumnLayout {
    id: root

    property var hyprland: null
    property string activeApp: ""
    property string activeWin: ""

    Layout.fillWidth: true
    spacing: Theme.Tokens.scaled(Theme.Tokens.spacingXs)

    function workspaceName(value) {
        if (!value || typeof value !== "object") return value ? String(value) : "";
        if (value.name !== undefined && value.name !== null) return String(value.name);
        if (value.id !== undefined && value.id !== null) return String(value.id);
        return "";
    }

    readonly property string activeName: workspaceName(hyprland ? hyprland.activeWorkspace : null)
    readonly property int windowCount: hyprland && hyprland.windows ? hyprland.windows.length : 0
    readonly property int occupiedCount: {
        if (!hyprland || !hyprland.workspaces) return 0;
        var count = 0;
        for (var i = 0; i < hyprland.workspaces.length; i++)
            if (Number(hyprland.workspaces[i].windows || 0) > 0) count++;
        return count;
    }

    Local.DashboardSection {
        Layout.fillWidth: true
        headline: "Active  " + (root.activeName !== "" ? root.activeName : "—")
        details: [
            { text: root.activeApp !== ""
                ? root.activeApp + "  ·  " + root.activeWin
                : "No focused application", color: Theme.Tokens.textSecondary },
            { text: "Windows  " + root.windowCount + "  ·  Occupied workspaces  " + root.occupiedCount }
        ]
        footnote: "Scroll the workspace capsule to switch."
    }
}