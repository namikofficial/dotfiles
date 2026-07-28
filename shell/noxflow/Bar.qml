import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "components"
import "theme" as Theme

PanelWindow {
    id: root
    required property var noxd; required property var hyprland; required property var audio
    required property var battery; required property var network; required property var bluetooth
    required property var media; required property var notificationModel; required property var systemModel
    property bool showNotificationBadge: !!(notificationModel && notificationModel.notifications && notificationModel.notifications.length > 0)
    property string monitorName: screen && screen.name ? screen.name : ""
    property var workspaceEntries: buildWorkspaceEntries()
    property var monitor: findMonitor()
    property bool providerDegraded: hasDegradedProvider()
    property bool urgent: monitorUrgentCount() > 0
    readonly property bool reducedMotion: Theme.Tokens.reducedMotion

    function chipRect(item) { if (!item || !item.visible) return Qt.rect(0,0,0,0); var p = item.mapToItem(null,0,0); return Qt.rect(p.x,p.y,item.width,item.height); }
    readonly property rect clockGeometry: chipRect(clockChip)
    readonly property rect mediaChipGeometry: chipRect(mediaChip)
    readonly property rect notificationChipGeometry: chipRect(notifChip)
    readonly property rect statusClusterGeometry: chipRect(statusCluster)

    function registerMorphChips() { var reg = shellRoot.morphRegistry; if (!reg) return; reg.registerChip("clock",clockGeometry); reg.registerChip("media",mediaChipGeometry); reg.registerChip("notification",notificationChipGeometry); reg.registerChip("status",statusClusterGeometry); }
    Component.onCompleted: registerMorphChips()

    screen: root.screen
    anchors.top: true; anchors.left: true; anchors.right: true
    exclusiveZone: Theme.Tokens.scaled(Theme.Tokens.heightToolbar)
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightToolbar)
    color: "transparent"

    function objectValue(object, first, second, fallback) { if (object && object[first] !== undefined && object[first] !== null) return object[first]; if (object && second && object[second] !== undefined && object[second] !== null) return object[second]; return fallback; }
    function workspaceId(value) { if (value && typeof value === "object") return objectValue(value, "id", "name", ""); return value === undefined || value === null ? "" : String(value); }
    function findMonitor() { for (var i = 0; i < hyprland.monitors.length; i++) if (String(hyprland.monitors[i].name || "") === monitorName) return hyprland.monitors[i]; return null; }
    function buildWorkspaceEntries() { var e = []; for (var i = 1; i <= 10; i++) e.push(String(i)); for (var j = 0; j < hyprland.workspaces.length; j++) { var n = String(hyprland.workspaces[j].name || ""); if (n && n.indexOf("special:") !== 0 && e.indexOf(n) < 0) e.push(n); } return e; }
    function workspaceRecord(name) { for (var i = 0; i < hyprland.workspaces.length; i++) { var item = hyprland.workspaces[i]; if (String(item.name || item.id) === name && String(item.monitor || "") === monitorName) return item; } return null; }
    function monitorActiveWorkspace() { return workspaceId(monitor ? objectValue(monitor, "activeWorkspace", "active_workspace", null) : null); }
    function workspaceOccupied(name) { for (var i = 0; i < hyprland.windows.length; i++) { var w = hyprland.windows[i]; var ws = w.workspace; if (ws && workspaceId(ws) === name && workspaceRecord(name)) return true; } return false; }
    function monitorUrgentCount() { var c = 0; for (var i = 0; i < hyprland.windows.length; i++) { var w = hyprland.windows[i]; if (hyprland.urgentWindows.indexOf(String(w.address||"")) >= 0 && workspaceRecord(workspaceId(w.workspace))) c++; } return c; }
    function workspaceUrgent(name) { for (var i = 0; i < hyprland.windows.length; i++) { var w = hyprland.windows[i]; if (workspaceId(w.workspace) === name && hyprland.urgentWindows.indexOf(String(w.address||"")) >= 0 && workspaceRecord(name)) return true; } return false; }
    function hasDegradedProvider() { var statuses = noxd.providerHealth || {}; for (var p in statuses) if (statuses[p] === "degraded") return true; return false; }
    function focusWorkspace(name) { noxd.runAction({ workspace_focus: { workspace: name } }); }
    function cycleWorkspace(delta) { noxd.runAction({ workspace_cycle: { delta: delta } }); }
    function toggleOutputMute() { noxd.runAction({ audio_toggle_mute: { target: "output" } }); }
    function refreshNetwork() { noxd.runAction({ network_refresh: {} }); }
    function toggleBluetooth() { noxd.runAction({ bluetooth_set_powered: { powered: !bluetooth.powered } }); }
    function toggleMediaPlayback() { noxd.runAction({ media_play_pause: {} }); }
    function activeWindowLabel() { var w = hyprland.activeWindow; if (!w || typeof w !== "object") return "Desktop"; return String(w.title || w.application_id || w.class || w.appid || "").trim() || "Desktop"; }
    function mediaLabel() { if (media.status !== "available" || !media.active || !media.title) return ""; var artist = media.artists && media.artists.length ? " — " + media.artists.join(", ") : ""; return media.title + artist; }
    function networkLabel() { if (network.status !== "available") return ""; if (network.connectivity === "full" || network.connectivity === "limited") return network.connectedSsid || "Network"; if (network.ethernet && network.ethernet.length) return "Ethernet"; return "Offline"; }
    function bluetoothLabel() { if (bluetooth.status !== "available" || !bluetooth.adapterPresent) return ""; for (var i = 0; i < bluetooth.devices.length; i++) if (bluetooth.devices[i].connected === true) return bluetooth.devices[i].name || "Bluetooth"; return bluetooth.powered ? "Bluetooth" : ""; }

    Rectangle {
        anchors.fill: parent
        color: Theme.Tokens.surfaceSurfaceContainerLow
        border.color: Theme.Tokens.outlineSubtle; border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
            anchors.rightMargin: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
            spacing: Theme.Tokens.scaled(Theme.Tokens.spacingSm)

            // Left: workspace pills + app name
            RowLayout { Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: Theme.Tokens.scaled(Theme.Tokens.spacingXs)
                Repeater {
                    model: root.workspaceEntries
                    delegate: FocusScope {
                        id: wsb; required property string modelData; required property int index
                        property bool ho: false; property bool pr: false
                        property bool active: root.monitorActiveWorkspace() === modelData
                        property bool occupied: root.workspaceOccupied(modelData)
                        property bool urg: root.workspaceUrgent(modelData)
                        implicitWidth: Math.max(Theme.Tokens.scaled(28), lbl.implicitWidth + Theme.Tokens.scaled(16))
                        implicitHeight: Theme.Tokens.scaled(28)
                        Accessible.role: Accessible.Button
                        Accessible.name: "Workspace "+modelData+(active?", active":occupied?", occupied":"")
                        Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill
                            color: wsb.pr ? Theme.Tokens.withAlpha(Theme.Tokens.statePressedOverlay,0.16) : wsb.active ? Theme.Tokens.tonalPrimaryContainer : wsb.ho ? Theme.Tokens.surfaceSurfaceContainerHighest : "transparent"
                            border.color: wsb.activeFocus ? Theme.Tokens.outlineFocus : wsb.occupied ? Theme.Tokens.outlineDefault : "transparent"
                            border.width: wsb.activeFocus ? 2 : wsb.occupied ? 1 : 0 }
                        Text { id: lbl; anchors.centerIn: parent; text: modelData
                            color: wsb.active ? Theme.Tokens.tonalOnPrimaryContainer : wsb.occupied ? Theme.Tokens.textPrimary : Theme.Tokens.textMuted
                            font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                        Rectangle { visible: wsb.urg; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 1; width: 5; height: 5; radius: 3; color: Theme.Tokens.stateDanger }
                        HoverHandler { onHoveredChanged: wsb.ho = hovered }
                        TapHandler { onPressedChanged: wsb.pr = pressed; onTapped: { wsb.forceActiveFocus(); root.focusWorkspace(modelData); } }
                        WheelHandler { onWheel: function(e) { root.cycleWorkspace(e.angleDelta.y > 0 ? -1 : 1); e.accepted = true; } }
                    }
                }
                Text { Layout.maximumWidth: Theme.Tokens.scaled(200); Layout.fillWidth: true; elide: Text.ElideRight
                    text: root.activeWindowLabel(); color: Theme.Tokens.textSecondary
                    font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyBodySmall }
                Text { visible: root.urgent; text: "\uF06A"; color: Theme.Tokens.stateDanger
                    font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyTitleMedium }
            }

            // Media chip
            FocusScope {
                id: mediaChip; property bool ho: false; visible: mediaText.text !== ""
                implicitWidth: mediaRow.implicitWidth + Theme.Tokens.scaled(16); implicitHeight: Theme.Tokens.scaled(28)
                Layout.maximumWidth: Theme.Tokens.scaled(260)
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: mediaChip.ho ? Theme.Tokens.surfaceSurfaceContainerHighest : "transparent" }
                RowLayout { id: mediaRow; anchors.centerIn: parent; spacing: Theme.Tokens.spacingXs
                    Text { text: "\uF001"; color: Theme.Tokens.tonalSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    Text { id: mediaText; Layout.maximumWidth: Theme.Tokens.scaled(240); elide: Text.ElideRight; text: root.mediaLabel(); color: Theme.Tokens.tonalSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                }
                HoverHandler { onHoveredChanged: mediaChip.ho = hovered }
                TapHandler { onTapped: { root.toggleMediaPlayback(); mediaChip.forceActiveFocus(); } }
                Accessible.name: mediaText.text !== "" ? "Media: " + mediaText.text : ""
            }

            // Right status cluster
            RowLayout { id: statusCluster; Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.alignment: Qt.AlignRight; spacing: Theme.Tokens.scaled(6)

                // Network pill
                FocusScope { id: nc; property bool ho: false; visible: root.networkLabel() !== ""
                    implicitWidth: nr.implicitWidth + Theme.Tokens.scaled(16); implicitHeight: Theme.Tokens.scaled(28)
                    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: nc.ho ? Theme.Tokens.surfaceSurfaceContainerHighest : "transparent" }
                    RowLayout { id: nr; anchors.centerIn: parent; spacing: 4
                        Text { text: "\uF1EB"; color: Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                        Text { text: root.networkLabel(); color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall; elide: Text.ElideRight }
                    }
                    HoverHandler { onHoveredChanged: nc.ho = hovered }
                    TapHandler { onTapped: { root.refreshNetwork(); nc.forceActiveFocus(); } }
                    Accessible.name: "Network: " + root.networkLabel() }

                // Bluetooth pill
                FocusScope { id: bc; property bool ho: false; visible: root.bluetoothLabel() !== ""
                    implicitWidth: br.implicitWidth + Theme.Tokens.scaled(16); implicitHeight: Theme.Tokens.scaled(28)
                    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: bc.ho ? Theme.Tokens.surfaceSurfaceContainerHighest : "transparent" }
                    RowLayout { id: br; anchors.centerIn: parent; spacing: 4
                        Text { text: "\uF294"; color: Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                        Text { text: root.bluetoothLabel(); color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    }
                    HoverHandler { onHoveredChanged: bc.ho = hovered }
                    TapHandler { onTapped: { root.toggleBluetooth(); bc.forceActiveFocus(); } }
                    Accessible.name: "Bluetooth: " + root.bluetoothLabel() }

                // Volume pill
                FocusScope { id: vc; property bool ho: false; visible: audio.status === "available"
                    implicitWidth: vr.implicitWidth + Theme.Tokens.scaled(16); implicitHeight: Theme.Tokens.scaled(28)
                    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: vc.ho ? Theme.Tokens.surfaceSurfaceContainerHighest : "transparent" }
                    RowLayout { id: vr; anchors.centerIn: parent; spacing: 4
                        Text { text: audio.outputMuted ? "\uF026" : "\uF028"; color: audio.outputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                        Text { text: audio.outputVolumePercent + "%"; color: audio.outputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall; visible: !audio.outputMuted }
                    }
                    HoverHandler { onHoveredChanged: vc.ho = hovered }
                    TapHandler { onTapped: { root.toggleOutputMute(); vc.forceActiveFocus(); } }
                    Accessible.name: "Volume: " + (audio.outputMuted ? "muted" : audio.outputVolumePercent + " percent") }

                // Battery pill
                FocusScope { id: batc; property bool ho: false; visible: battery.status === "available" && battery.present && battery.percentage !== null
                    implicitWidth: batr.implicitWidth + Theme.Tokens.scaled(16); implicitHeight: Theme.Tokens.scaled(28)
                    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: batc.ho ? Theme.Tokens.surfaceSurfaceContainerHighest : "transparent" }
                    RowLayout { id: batr; anchors.centerIn: parent; spacing: 4
                        Text { text: battery.charging ? "\uF1E6" : battery.critical ? "\uF244" : "\uF240"; color: battery.critical ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                        Text { text: Math.round(battery.percentage) + "%"; color: battery.critical ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    }
                    HoverHandler { onHoveredChanged: batc.ho = hovered }
                    Accessible.name: "Battery: " + Math.round(battery.percentage) + "%" }

                // Notification pill
                FocusScope { id: notifChip; property bool ho: false
                    implicitWidth: notifR.implicitWidth + Theme.Tokens.scaled(16); implicitHeight: Theme.Tokens.scaled(28)
                    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: notifChip.ho ? Theme.Tokens.surfaceSurfaceContainerHighest : "transparent" }
                    RowLayout { id: notifR; anchors.centerIn: parent; spacing: 4
                        Text { text: root.showNotificationBadge ? "\uF0F3" : "\uF0A2"; color: root.showNotificationBadge ? Theme.Tokens.stateInfo : Theme.Tokens.textMuted; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                        Text { visible: root.showNotificationBadge; text: root.notificationModel && root.notificationModel.notifications ? String(root.notificationModel.notifications.length) : ""; color: Theme.Tokens.stateInfo; font.pixelSize: Theme.Tokens.typographyLabelSmall; font.bold: true }
                    }
                    HoverHandler { onHoveredChanged: notifChip.ho = hovered }
                    TapHandler { onTapped: shellRoot.toggleNotificationCentre() }
                    Accessible.role: Accessible.Button
                    Accessible.name: root.showNotificationBadge ? root.notificationModel.notifications.length + " notifications" : "No notifications" }

                // Health dot
                Rectangle { visible: root.providerDegraded; width: 8; height: 8; radius: 4; color: Theme.Tokens.stateWarning
                    HoverHandler {} }
            }
        }

        // Clock pill (centered)
        FocusScope {
            id: clockChip; anchors.centerIn: parent; z: 10; property bool ho: false
            implicitWidth: cText.implicitWidth + Theme.Tokens.scaled(20); implicitHeight: Theme.Tokens.scaled(30)
            Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: clockChip.ho ? Theme.Tokens.surfaceSurfaceContainerHighest : "transparent" }
            Text { id: cText; anchors.centerIn: parent; text: Qt.formatTime(new Date(), "HH:mm");
                color: Theme.Tokens.textPrimary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyTitleMedium; font.bold: true
                Timer { interval: 1000; repeat: true; running: true; onTriggered: cText.text = Qt.formatTime(new Date(), "HH:mm") }
            }
            HoverHandler { onHoveredChanged: clockChip.ho = hovered }
            TapHandler { onTapped: shellRoot.toggleCalendar() }
            Accessible.name: "Current time: " + cText.text
        }
    }
}
