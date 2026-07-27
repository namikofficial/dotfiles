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
    required property var notificationModel
    required property var systemModel
    property bool showNotificationBadge: !!(notificationModel && notificationModel.notifications && notificationModel.notifications.length > 0)
    property string monitorName: screen && screen.name ? screen.name : ""
    property var workspaceEntries: buildWorkspaceEntries()
    property var monitor: findMonitor()
    property bool providerDegraded: hasDegradedProvider()
    property bool urgent: monitorUrgentCount() > 0

    // ── Morph-origin geometry (screen-space rects for Phase 3 MorphRegistry) ──
    function chipRect(item) {
        if (!item || !item.visible) return Qt.rect(0, 0, 0, 0);
        var p = item.mapToItem(null, 0, 0);
        return Qt.rect(p.x, p.y, item.width, item.height);
    }
    readonly property rect clockGeometry: chipRect(clockChip)
    readonly property rect mediaChipGeometry: chipRect(mediaChip)
    readonly property rect notificationChipGeometry: chipRect(notifChip)
    readonly property rect statusClusterGeometry: chipRect(statusCluster)

    // Register chips with MorphRegistry so panels can morph from them
    function registerMorphChips() {
        var reg = shellRoot.morphRegistry;
        if (!reg) return;
        reg.registerChip("clock", clockGeometry);
        reg.registerChip("media", mediaChipGeometry);
        reg.registerChip("notification", notificationChipGeometry);
        reg.registerChip("status", statusClusterGeometry);
    }
    Component.onCompleted: registerMorphChips()

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

    function toggleOutputMute() {
        noxd.runAction({ audio_toggle_mute: { target: "output" } });
    }

    function refreshNetwork() {
        noxd.runAction({ network_refresh: {} });
    }

    function toggleBluetooth() {
        noxd.runAction({ bluetooth_set_powered: { powered: !bluetooth.powered } });
    }

    function toggleMediaPlayback() {
        noxd.runAction({ media_play_pause: {} });
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
                        property bool pressed: false
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
                            color: workspaceButton.pressed ? Theme.Tokens.withAlpha(Theme.Tokens.statePressedOverlay, 0.16) : workspaceButton.active ? Theme.Tokens.tonalPrimaryContainer : workspaceButton.hovered ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent"
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
                        TapHandler {
                            onPressedChanged: workspaceButton.pressed = pressed
                            onTapped: {
                                workspaceButton.forceActiveFocus();
                                root.focusWorkspace(modelData);
                            }
                        }
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

            FocusScope {
                id: mediaChip
                property bool hovered: false
                visible: mediaText.text !== ""
                implicitWidth: mediaRow.implicitWidth + Theme.Tokens.scaled(Theme.Tokens.spacingMd)
                implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)
                Layout.maximumWidth: Theme.Tokens.scaled(280)

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.Tokens.radiusSm
                    color: mediaChip.hovered ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent"
                }
                RowLayout {
                    id: mediaRow
                    anchors.centerIn: parent
                    Text {
                        id: mediaText
                        Layout.maximumWidth: Theme.Tokens.scaled(260)
                        elide: Text.ElideRight
                        text: root.mediaLabel()
                        color: Theme.Tokens.tonalSecondary
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyBodySmall
                    }
                }
                HoverHandler { onHoveredChanged: mediaChip.hovered = hovered }
                TapHandler { onTapped: { root.toggleMediaPlayback(); mediaChip.forceActiveFocus(); } }
                Accessible.name: mediaText.text !== "" ? "Media: " + mediaText.text : ""
                Tooltip { target: mediaChip; text: mediaText.text }
            }

            // ── Weather chip (guarded — may not fully resolve in Variants scope) ──
            FocusScope {
                id: weatherChip
                property bool hovered: false
                readonly property var _w: typeof shellRoot !== "undefined" && shellRoot ? shellRoot.weatherModel || null : null
                visible: _w && _w.condition !== ""
                implicitWidth: weatherRow.implicitWidth + Theme.Tokens.scaled(Theme.Tokens.spacingMd)
                implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)
                Layout.maximumWidth: Theme.Tokens.scaled(180)

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.Tokens.radiusSm
                    color: weatherChip.hovered ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent"
                }
                RowLayout {
                    id: weatherRow
                    anchors.centerIn: parent
                    spacing: Theme.Tokens.spacingXs
                    Text {
                        text: weatherChip._w ? Math.round(weatherChip._w.temperature) + "°" : "—"
                        color: Theme.Tokens.tonalSecondary
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyBodySmall
                        font.bold: true
                    }
                    Text {
                        text: weatherChip._w ? weatherChip._w.condition : ""
                        color: Theme.Tokens.textSecondary
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                        elide: Text.ElideRight
                        visible: text !== ""
                    }
                }
                HoverHandler { onHoveredChanged: weatherChip.hovered = hovered }
                TapHandler { onTapped: shellRoot.toggleDashboard() }
                Tooltip { target: weatherChip; text: weatherChip._w ? weatherChip._w.location + " — " + weatherChip._w.condition + ", " + Math.round(weatherChip._w.temperature) + "°C" : "" }
            }

            RowLayout {
                id: statusCluster
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignRight
                spacing: Theme.Tokens.scaled(Theme.Tokens.spacingSm)

                FocusScope {
                    id: networkChip
                    property bool hovered: false
                    visible: root.networkLabel() !== ""
                    implicitWidth: networkText.implicitWidth + Theme.Tokens.scaled(Theme.Tokens.spacingMd)
                    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)
                    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusSm; color: networkChip.hovered ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent" }
                    Text { id: networkText; anchors.centerIn: parent; text: "⌁ " + root.networkLabel(); color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall; elide: Text.ElideRight }
                    HoverHandler { onHoveredChanged: networkChip.hovered = hovered }
                    TapHandler { onTapped: { root.refreshNetwork(); networkChip.forceActiveFocus(); } }
                    Accessible.name: "Network: " + root.networkLabel()
                    Tooltip { target: networkChip; text: "Network: " + root.networkLabel() }
                }
                // CPU chip
                FocusScope {
                    id: cpuChip
                    property bool hovered: false
                    visible: true
                    implicitWidth: cpuText.implicitWidth + Theme.Tokens.scaled(Theme.Tokens.spacingMd)
                    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)
                    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusSm; color: cpuChip.hovered ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent" }
                    Text {
                        id: cpuText; anchors.centerIn: parent
                        text: "⚡ " + (typeof systemModel !== "undefined" && systemModel ? systemModel.cpuUsage + "%" : "--")
                        color: (typeof systemModel !== "undefined" && systemModel && systemModel.cpuUsage > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary
                        font.pixelSize: Theme.Tokens.typographyBodySmall
                    }
                    HoverHandler { onHoveredChanged: cpuChip.hovered = hovered }
                    Tooltip { target: cpuChip; text: "CPU: " + (typeof systemModel !== "undefined" && systemModel ? systemModel.cpuUsage + "% @ " + systemModel.cpuTemp + "°C" : "N/A") }
                }
                // RAM chip
                FocusScope {
                    id: ramChip
                    property bool hovered: false
                    visible: true
                    implicitWidth: ramText.implicitWidth + Theme.Tokens.scaled(Theme.Tokens.spacingMd)
                    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)
                    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusSm; color: ramChip.hovered ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent" }
                    Text {
                        id: ramText; anchors.centerIn: parent
                        text: "💾 " + (typeof systemModel !== "undefined" && systemModel ? systemModel.memPercent + "%" : "--")
                        color: (typeof systemModel !== "undefined" && systemModel && systemModel.memPercent > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary
                        font.pixelSize: Theme.Tokens.typographyBodySmall
                    }
                    HoverHandler { onHoveredChanged: ramChip.hovered = hovered }
                    Tooltip { target: ramChip; text: "RAM: " + (typeof systemModel !== "undefined" && systemModel ? Math.round(systemModel.memUsed / 1024) + "/" + Math.round(systemModel.memTotal / 1024) + " GB" : "N/A") }
                }
                FocusScope {
                    id: bluetoothChip
                    property bool hovered: false
                    visible: root.bluetoothLabel() !== ""
                    implicitWidth: bluetoothText.implicitWidth + Theme.Tokens.scaled(Theme.Tokens.spacingMd)
                    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)
                    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusSm; color: bluetoothChip.hovered ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent" }
                    Text { id: bluetoothText; anchors.centerIn: parent; text: "◈ " + root.bluetoothLabel(); color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    HoverHandler { onHoveredChanged: bluetoothChip.hovered = hovered }
                    TapHandler { onTapped: { root.toggleBluetooth(); bluetoothChip.forceActiveFocus(); } }
                    Accessible.name: "Bluetooth: " + root.bluetoothLabel()
                    Tooltip { target: bluetoothChip; text: "Bluetooth: " + root.bluetoothLabel() }
                }
                FocusScope {
                    id: volumeChip
                    property bool hovered: false
                    visible: audio.status === "available"
                    implicitWidth: volumeText.implicitWidth + Theme.Tokens.scaled(Theme.Tokens.spacingMd)
                    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)
                    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusSm; color: volumeChip.hovered ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent" }
                    Text { id: volumeText; anchors.centerIn: parent; text: audio.outputMuted ? "◌" : "◉ " + audio.outputVolume + "%"; color: audio.outputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    HoverHandler { onHoveredChanged: volumeChip.hovered = hovered }
                    TapHandler { onTapped: { root.toggleOutputMute(); volumeChip.forceActiveFocus(); } }
                    Accessible.name: "Volume: " + (audio.outputMuted ? "muted" : audio.outputVolume + " percent")
                    Tooltip { target: volumeChip; text: "Volume: " + (audio.outputMuted ? "muted" : audio.outputVolume + "%") }
                }
                FocusScope {
                    id: batteryChip
                    property bool hovered: false
                    visible: battery.status === "available" && battery.present && battery.percentage !== null
                    implicitWidth: batteryText.implicitWidth + Theme.Tokens.scaled(Theme.Tokens.spacingMd)
                    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)
                    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusSm; color: batteryChip.hovered ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent" }
                    Text { id: batteryText; anchors.centerIn: parent; text: "▰ " + Math.round(battery.percentage) + "%"; color: battery.critical ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    HoverHandler { onHoveredChanged: batteryChip.hovered = hovered }
                    Accessible.name: "Battery: " + batteryText.text
                    Tooltip { target: batteryChip; text: "Battery: " + Math.round(battery.percentage) + "%" }
                }
                FocusScope {
                    id: notifChip
                    property bool hovered: false
                    implicitWidth: notifText.implicitWidth + Theme.Tokens.scaled(Theme.Tokens.spacingMd)
                    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)
                    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusSm; color: notifChip.hovered ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent" }
                    Text {
                        id: notifText; anchors.centerIn: parent
                        text: root.showNotificationBadge ? root.notificationModel.notifications.length : "·"
                        color: root.showNotificationBadge ? Theme.Tokens.stateInfo : Theme.Tokens.textMuted
                        font.pixelSize: Theme.Tokens.typographyTitleMedium
                        font.bold: root.showNotificationBadge
                    }
                    HoverHandler { onHoveredChanged: notifChip.hovered = hovered }
                    TapHandler { onTapped: shellRoot.toggleNotificationCentre() }
                    Accessible.role: Accessible.Button
                    Accessible.name: root.showNotificationBadge ? root.notificationModel.notifications.length + " notifications" : "No notifications"
                    Tooltip { target: notifChip; text: root.showNotificationBadge ? root.notificationModel.notifications.length + " notification(s)" : "Notifications" }
                }
                FocusScope {
                    id: healthChip
                    property bool hovered: false
                    visible: root.providerDegraded
                    implicitWidth: healthText.implicitWidth + Theme.Tokens.scaled(Theme.Tokens.spacingMd)
                    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)
                    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusSm; color: healthChip.hovered ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent" }
                    Text { id: healthText; anchors.centerIn: parent; text: "⚠"; color: Theme.Tokens.stateWarning; font.pixelSize: Theme.Tokens.typographyTitleMedium }
                    HoverHandler { onHoveredChanged: healthChip.hovered = hovered }
                    Accessible.name: "Shell health degraded"
                    Tooltip { target: healthChip; text: "Shell health degraded" }
                }
            }
        }

        // Keep the clock independent from the variable-width content on either side.
        FocusScope {
            id: clockChip
            anchors.centerIn: parent
            z: 10
            property bool hovered: false
            implicitWidth: clock.implicitWidth + Theme.Tokens.scaled(Theme.Tokens.spacingMd)
            implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightIconButton)

            Rectangle {
                anchors.fill: parent
                radius: Theme.Tokens.radiusSm
                color: clockChip.hovered ? Theme.Tokens.surfaceSurfaceContainerHigh : "transparent"
            }
            Text {
                id: clock
                anchors.centerIn: parent
                text: Qt.formatTime(new Date(), "HH:mm")
                color: Theme.Tokens.textPrimary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyTitleMedium
                font.bold: true
                Timer {
                    interval: 1000
                    repeat: true
                    running: true
                    onTriggered: clock.text = Qt.formatTime(new Date(), "HH:mm")
                }
            }
            HoverHandler { onHoveredChanged: clockChip.hovered = hovered }
            TapHandler { onTapped: shellRoot.toggleCalendar() }
            Accessible.name: "Current time: " + clock.text
            Tooltip { target: clockChip; text: "Calendar" }
        }
    }
}
