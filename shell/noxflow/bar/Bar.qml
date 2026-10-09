import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../components" as Components
import "../theme" as Theme
import "WorkspaceModel.js" as WorkspaceModel
import "." as Local

// bar/Bar.qml — NoxFlow top bar. Layout only.
//
// Decision 6 sets the final arrangement:
//   Left:   workspaces, health capsule
//   Centre: the island (owned by TopChrome), which keeps the clock
//   Right:  tray, connectivity, audio/power, mic, notifications, updates
//
// The sync pill and the duplicate left-hand update slot were removed in phase 2.
// Workspace derivation lives in WorkspaceState.qml / WorkspaceModel.js, panel
// registration scheduling lives in MorphTriggers.qml, and every pill's
// appearance lives in a pill component. What remains here is where things sit
// and what they do.



Item {
    id: root

    // ── Inputs ──
    property var screen
    required property var noxd
    required property var hyprland
    required property var audio
    required property var battery
    required property var network
    required property var bluetooth
    required property var media
    required property var notificationModel
    required property var systemModel
    required property var transfer
    required property var syncthing
    required property var updates
    property var islandHost: null

    // ── Derived ──
    readonly property string monitorName: screen && screen.name ? screen.name : ""
    property string updateLaunchState: "idle"
    property string updateLaunchMessage: ""
    readonly property bool providerDegraded: hasDegradedProvider()
    readonly property bool urgent: workspaces.urgentCount > 0

    Local.WorkspaceState {
        id: workspaces
        hyprland: root.hyprland
        monitorName: root.monitorName
    }

    // ── Layout ──
    readonly property int outerMargin: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
    readonly property int groupGap: Theme.Tokens.scaled(Theme.Tokens.spacingMd)

    // ── Geometry ──
    function chipRect(item) {
        if (!item || !item.visible) return Qt.rect(0, 0, 0, 0);
        var p = item.mapToItem(null, 0, 0);
        return Qt.rect(p.x, p.y, item.width, item.height);
    }
    // The clock and the media chip both live inside the island surface.
    readonly property rect clockGeometry: islandGeometry()
    readonly property rect mediaChipGeometry: clockGeometry
    readonly property rect notificationGeometry: chipRect(notificationPill)
    readonly property rect networkGeometry: chipRect(connectivityCapsule.networkActionItem)
    readonly property rect bluetoothGeometry: chipRect(connectivityCapsule.bluetoothActionItem)
    readonly property rect volumeGeometry: chipRect(audioPowerCapsule.audioActionItem)
    readonly property rect batteryGeometry: chipRect(audioPowerCapsule.powerActionItem)

    function islandGeometry() {
        if (!islandHost || typeof islandHost.islandGeometry !== "function") return Qt.rect(0, 0, 0, 0);
        return islandHost.islandGeometry();
    }

    Local.MorphTriggers {
        id: morph
        registry: shellRoot.triggerRegistry
        bindings: root.triggerBindings
    }

    function triggerBindings() {
        var radius = Theme.Tokens.radiusPill;
        return [
            { panel: "calendar",       monitor: root.monitorName, geometry: root.clockGeometry,       cornerRadius: radius },
            { panel: "media",          monitor: root.monitorName, geometry: root.mediaChipGeometry,   cornerRadius: radius },
            { panel: "notifications",  monitor: root.monitorName, geometry: root.notificationGeometry, cornerRadius: radius },
            { panel: "quick-settings", monitor: root.monitorName, geometry: root.volumeGeometry,     cornerRadius: radius },
            { panel: "quick-settings", monitor: root.monitorName, geometry: root.networkGeometry,    cornerRadius: radius, triggerId: "network" },
            { panel: "quick-settings", monitor: root.monitorName, geometry: root.bluetoothGeometry,  cornerRadius: radius, triggerId: "bluetooth" },
            { panel: "quick-settings", monitor: root.monitorName, geometry: root.volumeGeometry,     cornerRadius: radius, triggerId: "volume" },
            { panel: "quick-settings", monitor: root.monitorName, geometry: root.batteryGeometry,    cornerRadius: radius, triggerId: "battery" }
        ];
    }

    // Re-measure when anything that changes a capsule's width changes.
    onWidthChanged: morph.requestRegistration()
    onVisibleChanged: if (visible) morph.registerAll()
    Component.onCompleted: { workspaces.refresh(); morph.registerAll(); }

    Connections {
        target: root.hyprland
        function onWorkspacesChanged() { workspaces.refresh(); morph.requestRegistration(); }
        function onWindowsChanged() { workspaces.refresh(); morph.requestRegistration(); }
        function onActiveWorkspaceChanged() { workspaces.confirmPending(); morph.requestRegistration(); }
        function onFocusedMonitorChanged() { workspaces.refresh(); morph.requestRegistration(); }
        function onMonitorsChanged() { workspaces.refresh(); morph.requestRegistration(); }
    }
    Connections {
        target: root.audio
        function onOutputVolumeChanged() { morph.requestRegistration() }
        function onHasSyncedChanged() { morph.requestRegistration() }
    }
    Connections {
        target: root.updates
        function onCountChanged() { morph.requestRegistration() }
        function onCheckedChanged() { morph.requestRegistration() }
    }
    Connections {
        target: root.media
        function onStatusChanged() { morph.requestRegistration() }
    }

    function hasDegradedProvider() {
        var health = noxd.providerHealth || {};
        for (var provider in health) if (health[provider] === "degraded") return true;
        return false;
    }

    // ── Update launcher ──
    property Components.Command updateProcess: Components.Command {
        label: "Update terminal"
        onExited: function(code) {
            // stdout and stderr are the same "did it open" channel here, so the
            // message is whichever one actually produced output.
            root.updateLaunchMessage = root.updateProcess.output.trim()
                || root.updateProcess.errorOutput.trim();
            root.updateLaunchState = code === 0 ? "opened" : "failed";
            if (code !== 0 && root.updateLaunchMessage === "")
                root.updateLaunchMessage = "Update terminal failed to open";
            updateStateTimer.restart();
        }
    }
    Timer {
        id: updateStateTimer
        interval: 3500
        onTriggered: { root.updateLaunchState = "idle"; root.updateLaunchMessage = ""; }
    }

    function runSystemUpdate() {
        if (updateProcess.running) return;
        updateLaunchState = "opening";
        updateLaunchMessage = "Opening update terminal…";
        updateProcess.command = ["sh", "-lc", "exec \"$HOME/.config/hypr/scripts/system-update.sh\""];
        updateProcess.running = true;
    }

    // ── Panel toggles ──
    function toggleCalendar() { shellRoot.coordinator.toggle("calendar", monitorName, clockGeometry); }
    function toggleNotifications() { shellRoot.coordinator.toggle("notifications", monitorName, notificationGeometry); }
    function toggleMedia() { shellRoot.coordinator.toggle("media", monitorName, mediaChipGeometry); }
    function toggleQuickSettings(sourceItem, section) {
        shellRoot.coordinator.toggle("quick-settings", monitorName,
                                     chipRect(sourceItem || rightZone), section || "");
    }

    // ── Daemon actions ──
    function toggleMute() { noxd.runAction({ audio_toggle_mute: { target: "output" } }); }
    function adjustVolume(delta) { noxd.runAction({ audio_adjust_volume: { target: "output", delta: delta } }); }

    // ── Island hover bridge ──
    function islandHover(kind, hovered, source) {
        if (islandHost && typeof islandHost.sourceHoverChanged === "function")
            islandHost.sourceHoverChanged(kind, hovered, source);
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.outerMargin
        anchors.rightMargin: root.outerMargin
        spacing: root.groupGap

        // ── LEFT ──
        RowLayout {
            id: leftZone
            Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
            spacing: root.groupGap

            Local.WorkspaceCluster {
                id: cluster
                entries: workspaces.entries
                presentation: function (name) { return workspaces.presentation(name); }
                monitorName: root.monitorName
                onActivated: function (name) { workspaces.focus(name); }
                onCycled: function (direction) { workspaces.cycle(direction); }
                onHovered: function (name, hovered, pill) { root.islandHover("workspace", hovered, pill); }
            }

            Components.HealthCapsule {
                id: healthCapsule
                systemModel: root.systemModel
                Layout.alignment: Qt.AlignVCenter
                onOpenSystem: root.toggleQuickSettings(healthCapsule, "system")
                onHoveredChanged: function (hovered) {
                    root.islandHover("health", hovered, healthCapsule);
                }
            }
        }

        // Centre spacer — the island owns the middle of the screen.
        Item { Layout.fillWidth: true; Layout.minimumWidth: Theme.Tokens.scaled(20) }

        // ── RIGHT ──
        RowLayout {
            id: rightZone
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            spacing: root.groupGap

            Local.TrayCapsule {
                id: tray
                Layout.alignment: Qt.AlignVCenter
            }

            Components.ConnectivityCapsule {
                id: connectivityCapsule
                network: root.network
                bluetooth: root.bluetooth
                Layout.alignment: Qt.AlignVCenter
                onOpenNetwork: root.toggleQuickSettings(connectivityCapsule.networkActionItem, "network")
                onOpenBluetooth: root.toggleQuickSettings(connectivityCapsule.bluetoothActionItem, "bluetooth")
                onHoveredChanged: function (hovered) {
                    root.islandHover("connectivity", hovered, connectivityCapsule);
                }
            }

            Components.AudioPowerCapsule {
                id: audioPowerCapsule
                audio: root.audio
                battery: root.battery
                Layout.alignment: Qt.AlignVCenter
                onToggleMute: root.toggleMute()
                onAdjustVolume: function (delta) { root.adjustVolume(delta); }
                onOpenPower: root.toggleQuickSettings(audioPowerCapsule.powerActionItem, "battery")
                onHoveredChanged: function (hovered) {
                    root.islandHover("audio-power", hovered, audioPowerCapsule);
                }
            }

            Local.MicIndicator {
                id: micIndicator
                Layout.alignment: Qt.AlignVCenter
            }

            Local.NotificationPill {
                id: notificationPill
                count: root.notificationModel && root.notificationModel.notifications
                    ? root.notificationModel.notifications.length : 0
                dnd: !!(root.notificationModel && root.notificationModel.dnd)
                Layout.alignment: Qt.AlignVCenter
                onActivated: root.toggleNotifications()
                onHoverChangedToIsland: function (hovered) {
                    root.islandHover("notification-preview", hovered, notificationPill);
                }
            }

            Local.UpdatePill {
                id: updatePill
                launchState: root.updateLaunchState
                launchMessage: root.updateLaunchMessage
                checked: root.updates.checked
                count: root.updates.count
                detailTooltip: root.updates.tooltip
                Layout.alignment: Qt.AlignVCenter
                onRunUpdate: root.runSystemUpdate()
                onRefreshRequested: root.updates.refresh()
                onHoverChangedToIsland: function (hovered) {
                    root.islandHover("updates", hovered, updatePill);
                }
            }

            // Provider health dot — only visible when something is degraded.
            Rectangle {
                id: providerHealthDot
                visible: root.providerDegraded
                width: Theme.Tokens.scaled(8)
                height: Theme.Tokens.scaled(8)
                radius: Theme.Tokens.scaled(4)
                color: Theme.Tokens.stateWarning
                Layout.alignment: Qt.AlignVCenter
                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) root.islandHover("provider-health", true, providerHealthDot);
                    }
                }
            }
        }
    }
}