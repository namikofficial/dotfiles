import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "components"
import "theme" as Theme

PanelWindow {
    id: root

    required property var noxd
    required property var hyprland
    required property var audio
    required property var battery
    required property var network
    required property var bluetooth
    required property var media
    property string monitorName: screen && screen.name ? screen.name : ""
    property var workspaceEntries: buildWorkspaceEntries()
    property var monitor: findMonitor()
    property bool providerDegraded: hasDegradedProvider()
    property bool urgent: monitorUrgentCount() > 0

    screen: root.screen
    anchors.top: true
    anchors.left: true
    anchors.right: true
    exclusiveZone: Theme.Tokens.scaled(Theme.Tokens.heightToolbar)
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightToolbar)
    color: "transparent"

    function objectValue(object, first, second, fallback) {
        if (object && object[first] !== undefined && object[first] !== null) return object[first];
        if (object && second && object[second] !== undefined && object[second] !== null) return object[second];
        return fallback;
    }

    function workspaceId(value) {
        if (value && typeof value === "object") return objectValue(value, "id", "name", "");
        return value === undefined || value === null ? "" : String(value);
    }

    function findMonitor() {
        for (var i = 0; i < hyprland.monitors.length; i++) {
            if (String(hyprland.monitors[i].name || "") === monitorName) return hyprland.monitors[i];
        }
        return null;
    }

    function buildWorkspaceEntries() {
        var entries = [];
        for (var i = 1; i <= 10; i++) entries.push(String(i));
        for (var j = 0; j < hyprland.workspaces.length; j++) {
            var name = String(hyprland.workspaces[j].name || "");
            if (name && name.indexOf("special:") !== 0 && entries.indexOf(name) < 0) entries.push(name);
        }
        return entries;
    }

    function workspaceRecord(name) {
        for (var i = 0; i < hyprland.workspaces.length; i++) {
            var item = hyprland.workspaces[i];
            if (String(item.name || item.id) === name && String(item.monitor || "") === monitorName) return item;
        }
        return null;
    }

    function monitorActiveWorkspace() {
        return workspaceId(monitor ? objectValue(monitor, "activeWorkspace", "active_workspace", null) : null);
    }

    function workspaceOccupied(name) {
        for (var i = 0; i < hyprland.windows.length; i++) {
            var window = hyprland.windows[i];
            var workspace = window.workspace;
            if (workspace && workspaceId(workspace) === name) {
                var record = workspaceRecord(name);
                return record !== null;
            }
        }
        return false;
    }

    function monitorUrgentCount() {
        var count = 0;
        for (var i = 0; i < hyprland.windows.length; i++) {
            var window = hyprland.windows[i];
            var address = String(window.address || "");
            if (hyprland.urgentWindows.indexOf(address) >= 0) {
                var record = workspaceRecord(workspaceId(window.workspace));
                if (record) count++;
            }
        }
        return count;
    }

    function workspaceUrgent(name) {
        for (var i = 0; i < hyprland.windows.length; i++) {
            var window = hyprland.windows[i];
            if (workspaceId(window.workspace) === name && hyprland.urgentWindows.indexOf(String(window.address || "")) >= 0 && workspaceRecord(name)) return true;
        }
        return false;
    }

    function hasDegradedProvider() {
        var statuses = noxd.providerHealth || {};
        for (var provider in statuses) if (statuses[provider] === "degraded") return true;
        return false;
    }

    function focusWorkspace(name) {
        noxd.runAction({ workspace_focus: { workspace: name } });
    }

    function cycleWorkspace(delta) {
        noxd.runAction({ workspace_cycle: { delta: delta } });
    }

    function activeWindowLabel() {
        var window = hyprland.activeWindow;
        if (!window || typeof window !== "object") return "Desktop";
        var title = String(window.title || "").trim();
        var app = String(window.application_id || window.class || window.appid || "").trim();
        return title || app || "Desktop";
    }

    function mediaLabel() {
        if (media.status !== "available" || !media.active || !media.title) return "";
        var artist = media.artists.length ? " — " + media.artists.join(", ") : "";
        return media.title + artist;
    }

    function networkLabel() {
        if (network.status !== "available") return "";
        if (network.connectivity === "full" || network.connectivity === "limited") return network.connectedSsid || "Network";
        if (network.ethernet.length) return "Ethernet";
        return "Offline";
    }

    function bluetoothLabel() {
        if (bluetooth.status !== "available" || !bluetooth.adapterPresent) return "";
        for (var i = 0; i < bluetooth.devices.length; i++) {
            if (bluetooth.devices[i].connected === true) return bluetooth.devices[i].name || "Bluetooth";
        }
        return bluetooth.powered ? "Bluetooth" : "";
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.Tokens.surfaceSurfaceContainerLow
        border.color: Theme.Tokens.outlineSubtle
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
            anchors.rightMargin: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
            spacing: Theme.Tokens.scaled(Theme.Tokens.spacingSm)

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: Theme.Tokens.scaled(Theme.Tokens.spacingXs)

                Repeater {
                    model: root.workspaceEntries
                    delegate: FocusScope {
                        id: workspaceButton
                        required property string modelData
                        required property int index
                        property bool hovered: false
                        property bool active: root.monitorActiveWorkspace() === modelData
                        property bool occupied: root.workspaceOccupied(modelData)
                        property bool urgent: root.workspaceUrgent(modelData)
                        implicitWidth: Math.max(Theme.Tokens.scaled(Theme.Tokens.heightIconButton), label.implicitWidth + Theme.Tokens.scaled(Theme.Tokens.spacingMd))
                        implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)
                        focus: modelData === "1"
                        Accessible.role: Accessible.Button
                        Accessible.name: "Workspace " + modelData + (active ? ", active" : occupied ? ", occupied" : "")

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.Tokens.radiusSm
                            color: workspaceButton.active ? Theme.Tokens.tonalPrimaryContainer : workspaceButton.hovered ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent"
                            border.color: workspaceButton.activeFocus ? Theme.Tokens.outlineFocus : workspaceButton.occupied ? Theme.Tokens.outlineDefault : "transparent"
                            border.width: workspaceButton.activeFocus ? 2 : workspaceButton.occupied ? 1 : 0
                        }
                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: modelData
                            color: workspaceButton.active ? Theme.Tokens.tonalOnPrimaryContainer : workspaceButton.occupied ? Theme.Tokens.textPrimary : Theme.Tokens.textMuted
                            font.family: Theme.Tokens.typographyFontFamily
                            font.pixelSize: Theme.Tokens.typographyLabelMedium
                        }
                        Rectangle {
                            visible: workspaceButton.urgent
                            anchors.right: parent.right
                            anchors.top: parent.top
                            width: 6; height: 6; radius: 3
                            color: Theme.Tokens.stateDanger
                        }
                        HoverHandler { onHoveredChanged: workspaceButton.hovered = hovered }
                        TapHandler { onTapped: root.focusWorkspace(modelData) }
                        WheelHandler {
                            onWheel: function(event) {
                                root.cycleWorkspace(event.angleDelta.y > 0 ? -1 : 1);
                                event.accepted = true;
                            }
                        }
                        Keys.onReturnPressed: root.focusWorkspace(modelData)
                        Keys.onSpacePressed: root.focusWorkspace(modelData)
                        Keys.onLeftPressed: root.cycleWorkspace(-1)
                        Keys.onRightPressed: root.cycleWorkspace(1)
                        Tooltip { target: workspaceButton; text: "Workspace " + modelData }
                    }
                }

                Text {
                    Layout.maximumWidth: Theme.Tokens.scaled(220)
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.activeWindowLabel()
                    color: Theme.Tokens.textSecondary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyBodySmall
                    Accessible.name: "Active application: " + text
                }
                Text {
                    visible: root.urgent
                    text: "!"
                    color: Theme.Tokens.stateDanger
                    font.bold: true
                    font.pixelSize: Theme.Tokens.typographyTitleMedium
                    Accessible.name: "Urgent window"
                }
            }

            Text {
                Layout.alignment: Qt.AlignCenter
                text: Qt.formatTime(new Date(), "HH:mm")
                color: Theme.Tokens.textPrimary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyTitleMedium
                font.bold: true
                Timer { interval: 1000; repeat: true; running: true; onTriggered: parent.text = Qt.formatTime(new Date(), "HH:mm") }
                Accessible.name: "Current time: " + text
            }

            Text {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.maximumWidth: Theme.Tokens.scaled(280)
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
                text: root.mediaLabel()
                visible: text !== ""
                color: Theme.Tokens.tonalSecondary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyBodySmall
                Accessible.name: visible ? "Media: " + text : ""
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignRight
                spacing: Theme.Tokens.scaled(Theme.Tokens.spacingMd)

                Text {
                    property bool hovered: false
                    visible: root.networkLabel() !== ""
                    text: "⌁ " + root.networkLabel(); color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall; elide: Text.ElideRight; Accessible.name: "Network: " + text
                    HoverHandler { onHoveredChanged: parent.hovered = hovered }
                    Tooltip { target: parent; text: "Network: " + root.networkLabel() }
                }
                Text {
                    property bool hovered: false
                    visible: root.bluetoothLabel() !== ""
                    text: "◈ " + root.bluetoothLabel(); color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall; Accessible.name: "Bluetooth: " + text
                    HoverHandler { onHoveredChanged: parent.hovered = hovered }
                    Tooltip { target: parent; text: "Bluetooth: " + root.bluetoothLabel() }
                }
                Text {
                    property bool hovered: false
                    visible: audio.status === "available"
                    text: audio.outputMuted ? "◌" : "◉ " + audio.outputVolume + "%"; color: audio.outputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall; Accessible.name: "Volume: " + (audio.outputMuted ? "muted" : audio.outputVolume + " percent")
                    HoverHandler { onHoveredChanged: parent.hovered = hovered }
                    Tooltip { target: parent; text: "Volume: " + (audio.outputMuted ? "muted" : audio.outputVolume + "%") }
                }
                Text {
                    property bool hovered: false
                    visible: battery.status === "available" && battery.present && battery.percentage !== null
                    text: "▰ " + Math.round(battery.percentage) + "%"; color: battery.critical ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall; Accessible.name: "Battery: " + text
                    HoverHandler { onHoveredChanged: parent.hovered = hovered }
                    Tooltip { target: parent; text: "Battery: " + Math.round(battery.percentage) + "%" }
                }
                Text {
                    property bool hovered: false
                    text: "·"; color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyTitleMedium; Accessible.role: Accessible.Button; Accessible.name: "Notifications"
                    HoverHandler { onHoveredChanged: parent.hovered = hovered }
                    Tooltip { target: parent; text: "Notifications" }
                }
                Text {
                    property bool hovered: false
                    visible: root.providerDegraded
                    text: "⚠"; color: Theme.Tokens.stateWarning; font.pixelSize: Theme.Tokens.typographyTitleMedium; Accessible.name: "Shell health degraded"
                    HoverHandler { onHoveredChanged: parent.hovered = hovered }
                    Tooltip { target: parent; text: "Shell health degraded" }
                }
            }
        }
    }
}
