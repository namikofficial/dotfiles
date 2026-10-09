import QtQuick
import QtQuick.Layouts
import "../theme" as Theme
import "./bodies" as Bodies

// IslandDashboardBody.qml — the island's expanded dashboard content.
//
// One Loader keyed on the island kind. Each body is a component under
// island/bodies/, so adding a kind means adding a route entry AND a body —
// which is what makes "the island only keeps features that something triggers"
// checkable rather than aspirational.
//
// Bodies that no route points at are dead by construction.



ColumnLayout {
    id: root

    property string kind: "idle"
    property var hyprland: null
    property var systemModel: null
    property var network: null
    property var bluetooth: null
    property var audio: null
    property var battery: null
    property var notificationModel: null
    property var updates: null
    property string activeApp: ""
    property string activeWin: ""

    spacing: Theme.Tokens.scaled(8)

    readonly property var componentForKind: ({
        "workspace": Bodies.WorkspaceBody,
        "health": Bodies.HealthBody,
        "connectivity": Bodies.ConnectivityBody,
        "audio-power": Bodies.AudioPowerBody,
        "notification-preview": Bodies.NotificationPreviewBody,
        "updates": Bodies.UpdatesBody,
        "provider-health": Bodies.ProviderHealthBody
    })

    Loader {
        Layout.fillWidth: true
        Layout.fillHeight: true
        active: root.componentForKind[root.kind] !== undefined
        sourceComponent: root.componentForKind[root.kind] || null
        // The models are plain properties on the host, so they must be handed
        // down explicitly rather than resolved from the delegate's scope.
        onLoaded: {
            item.hyprland = root.hyprland;
            item.systemModel = root.systemModel;
            item.network = root.network;
            item.bluetooth = root.bluetooth;
            item.audio = root.audio;
            item.battery = root.battery;
            item.notificationModel = root.notificationModel;
            item.updates = root.updates;
            item.activeApp = root.activeApp;
            item.activeWin = root.activeWin;
        }
    }

    // Shown when a dashboard kind has no body. A silent blank panel reads as a
    // rendering bug, so say what is missing.
    Bodies.DashboardSection {
        Layout.fillWidth: true
        visible: !root.componentForKind[root.kind]
        headline: "No content for " + root.kind
        headlineColor: Theme.Tokens.stateWarning
        footnote: "This island kind has no dashboard body. That means the route table and the body list disagree."
        footnoteWrap: true
    }
}