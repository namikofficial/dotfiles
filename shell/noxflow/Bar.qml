// Bar.qml — NoxFlow top bar with three-zone layout.
// Left: workspace cluster + health capsule
// Center: spacer (island lives in TopChrome)
// Right: connectivity | audio/power | notifications | updates

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "components"
import "theme" as Theme
import "WorkspacePresentation.js" as WorkspacePresentation

Item {
    id: root
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

    // ── Derived state ──
    property bool showNotificationBadge: !!(notificationModel && notificationModel.notifications && notificationModel.notifications.length > 0)
    property string monitorName: screen && screen.name ? screen.name : ""
    property var workspaceEntries: []
    property var monitor: findMonitor()
    property bool providerDegraded: hasDegradedProvider()
    property bool urgent: monitorUrgentCount() > 0
    property string pendingWorkspace: ""

    // Workspace dispatch (hyprctl eval form for Hyprland 0.56+)
    property Process workspaceDispatch: Process {
        running: false
        onExited: function(code) {
            if (code !== 0) root.pendingWorkspace = "";
            else workspacePendingTimer.restart();
        }
    }
    Timer { id: workspacePendingTimer; interval: 1200; onTriggered: root.pendingWorkspace = "" }

    // Update launch state
    property string updateLaunchState: "idle"
    property string updateLaunchMessage: ""
    property Process updateProcess: Process {
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) { root.updateLaunchMessage = String(data).trim(); }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function(data) { root.updateLaunchMessage = String(data).trim(); }
        }
        onExited: function(code) {
            root.updateLaunchState = code === 0 ? "opened" : "failed";
            if (code !== 0 && root.updateLaunchMessage === "") root.updateLaunchMessage = "Update terminal failed to open";
            updateStateTimer.restart();
        }
    }
    Timer {
        id: updateStateTimer
        interval: 3500
        onTriggered: { root.updateLaunchState = "idle"; root.updateLaunchMessage = ""; }
    }

    // ── Layout constants ──
    readonly property bool reducedMotion: Theme.Tokens.reducedMotion
    readonly property int outerMargin: Theme.Tokens.scaled(8)
    readonly property int groupGap: Theme.Tokens.scaled(10)
    readonly property int innerGap: Theme.Tokens.scaled(5)
    readonly property int capsulePadH: Theme.Tokens.scaled(12)
    readonly property int capsulePadV: Theme.Tokens.scaled(9)

    // ── Morph registration ──
    function chipRect(item) { if (!item || !item.visible) return Qt.rect(0, 0, 0, 0); var p = item.mapToItem(null, 0, 0); return Qt.rect(p.x, p.y, item.width, item.height); }
    readonly property rect clockGeometry: islandHost && typeof islandHost.islandGeometry === "function" ? islandHost.islandGeometry() : Qt.rect(0, 0, 0, 0)
    readonly property rect mediaChipGeometry: islandHost && typeof islandHost.islandGeometry === "function" ? islandHost.islandGeometry() : Qt.rect(0, 0, 0, 0)
    readonly property rect notificationChipGeometry: chipRect(notifPill)
    readonly property rect statusClusterGeometry: chipRect(rightZone)
    readonly property rect healthGeometry: chipRect(healthCapsule)
    readonly property rect networkGeometry: chipRect(connectivityCapsule)
    readonly property rect volumeGeometry: chipRect(audioPowerCapsule)
    readonly property rect batteryGeometry: chipRect(audioPowerCapsule)
    readonly property rect syncGeometry: chipRect(syncPill)

    function registerMorphChips() {
        var reg = shellRoot.triggerRegistry;
        if (!reg) return;
        reg.registerTrigger("calendar", monitorName, clockGeometry, Theme.Tokens.radiusPill);
        reg.registerTrigger("media", monitorName, mediaChipGeometry, Theme.Tokens.radiusPill);
        reg.registerTrigger("notifications", monitorName, notificationChipGeometry, Theme.Tokens.radiusPill);
        reg.registerTrigger("quick-settings", monitorName, volumeGeometry, Theme.Tokens.radiusPill);
        reg.registerTrigger("quick-settings", monitorName, networkGeometry, Theme.Tokens.radiusPill, "network");
        reg.registerTrigger("quick-settings", monitorName, volumeGeometry, Theme.Tokens.radiusPill, "volume");
        reg.registerTrigger("quick-settings", monitorName, batteryGeometry, Theme.Tokens.radiusPill, "battery");
        reg.registerTrigger("sync", monitorName, syncGeometry, Theme.Tokens.radiusPill);
    }
    Timer { interval: 250; repeat: true; running: root.visible; onTriggered: { root.registerMorphChips(); root.refreshWorkspaceEntries(); } }

    Component.onCompleted: { registerMorphChips(); refreshWorkspaceEntries(); }

    Connections {
        target: root.hyprland
        function onWorkspacesChanged() { root.refreshWorkspaceEntries(); }
        function onWindowsChanged() { root.refreshWorkspaceEntries(); }
        function onActiveWorkspaceChanged() {
            if (root.pendingWorkspace !== "" && root.wsId(root.hyprland.activeWorkspace) === root.pendingWorkspace) {
                root.pendingWorkspace = "";
                workspacePendingTimer.stop();
            }
            root.refreshWorkspaceEntries();
        }
        function onFocusedMonitorChanged() { root.refreshWorkspaceEntries(); }
        function onMonitorsChanged() { root.refreshWorkspaceEntries(); }
    }

    // ── Workspace helpers (delegated to WorkspaceCluster for display; kept for morph registration) ──
    function objVal(o, a, b, f) { if (o && o[a] !== undefined && o[a] !== null) return o[a]; if (o && b && o[b] !== undefined && o[b] !== null) return o[b]; return f; }
    function wsId(v) { return WorkspacePresentation.workspaceId(v); }
    function monitorId() { return monitor && monitor.id !== undefined ? Number(monitor.id) : -1; }
    function findMonitor() { for (var i = 0; i < hyprland.monitors.length; i++) if (String(hyprland.monitors[i].name || "") === monitorName) return hyprland.monitors[i]; return null; }
    function buildWorkspaceEntries() {
        var e = [];
        var mon = monitorName;
        for (var j = 0; j < hyprland.workspaces.length; j++) {
            var w = hyprland.workspaces[j];
            if (!w) continue;
            var n = String(w.name !== undefined && w.name !== null ? w.name : w.id);
            if (!n || n.indexOf("special:") === 0) continue;
            if (mon !== "" && String(w.monitor || "") !== mon) continue;
            if (Number(w.windows || 0) <= 0 && n !== monitorActiveWS()) continue;
            if (e.indexOf(n) < 0) e.push(n);
        }
        for (var k = 0; k < hyprland.windows.length; k++) {
            var client = hyprland.windows[k];
            if (!client || !client.workspace) continue;
            var clientWorkspace = client.workspace;
            var clientName = String(clientWorkspace.name !== undefined && clientWorkspace.name !== null ? clientWorkspace.name : clientWorkspace.id);
            if (!clientName || clientName.indexOf("special:") === 0) continue;
            var clientMonitor = client.monitorName !== undefined ? String(client.monitorName) : String(client.monitor !== undefined ? client.monitor : "");
            if (mon !== "" && clientMonitor !== "" && clientMonitor !== mon && Number(client.monitor) !== root.monitorId()) continue;
            if (e.indexOf(clientName) < 0) e.push(clientName);
        }
        var active = monitorActiveWS();
        if (active !== "" && e.indexOf(active) < 0) e.push(active);
        e.sort(function(a, b) {
            var na = parseInt(a, 10), nb = parseInt(b, 10);
            if (!isNaN(na) && !isNaN(nb)) return na - nb;
            if (!isNaN(na)) return -1;
            if (!isNaN(nb)) return 1;
            return a < b ? -1 : a > b ? 1 : 0;
        });
        return e;
    }
    function refreshWorkspaceEntries() {
        var next = buildWorkspaceEntries();
        if (JSON.stringify(next) !== JSON.stringify(workspaceEntries)) workspaceEntries = next;
    }
    function wsRecord(name) { for (var i = 0; i < hyprland.workspaces.length; i++) { var it = hyprland.workspaces[i]; if (String(it.name || it.id) === name && String(it.monitor || "") === monitorName) return it; } return null; }
    function monitorActiveWS() {
        if (pendingWorkspace !== "") return pendingWorkspace;
        if (hyprland.focusedMonitor === monitorName && hyprland.activeWorkspace) return wsId(hyprland.activeWorkspace);
        return wsId(monitor ? objVal(monitor, "activeWorkspace", "active_workspace", null) : null);
    }
    function wsOccupied(name) { for (var i = 0; i < hyprland.windows.length; i++) { var w = hyprland.windows[i]; var ws = w.workspace; if (ws && wsId(ws) === name && wsRecord(name)) return true; } return false; }
    function monitorUrgentCount() { var c = 0; for (var i = 0; i < hyprland.windows.length; i++) { var w = hyprland.windows[i]; if (hyprland.urgentWindows.indexOf(String(w.address || "")) >= 0 && wsRecord(wsId(w.workspace))) c++; } return c; }
    function wsUrgent(name) { for (var i = 0; i < hyprland.windows.length; i++) { var w = hyprland.windows[i]; if (wsId(w.workspace) === name && hyprland.urgentWindows.indexOf(String(w.address || "")) >= 0 && wsRecord(name)) return true; } return false; }
    function hasDegradedProvider() { var ss = noxd.providerHealth || {}; for (var p in ss) if (ss[p] === "degraded") return true; return false; }

    function focusWS(name) {
        var target = String(name || "").trim();
        if (!target || target.indexOf("special:") === 0 || !/^[0-9A-Za-z_-]+$/.test(target)) return;
        pendingWorkspace = target;
        refreshWorkspaceEntries();
        workspaceDispatch.running = false;
        workspaceDispatch.command = ["hyprctl", "eval", "hl.dispatch(hl.dsp.focus({ workspace = \"" + target + "\" }))"];
        workspaceDispatch.running = true;
    }

    function cycleWS(d) {
        var direction = d < 0 ? "e-1" : "e+1";
        workspaceDispatch.running = false;
        workspaceDispatch.command = ["hyprctl", "eval", "hl.dispatch(hl.dsp.focus({ workspace = \"" + direction + "\" }))"];
        workspaceDispatch.running = true;
    }

    // ── Actions ──
    function toggleMute() { noxd.runAction({audio_toggle_mute: {target: "output"}}); }
    function adjustVolume(delta) { noxd.runAction({audio_adjust_volume: {target: "output", delta: delta}}); }
    function runSystemUpdate() {
        if (updateProcess.running) return;
        updateLaunchState = "opening";
        updateLaunchMessage = "Opening update terminal…";
        updateProcess.command = ["sh", "-lc", "exec \"$HOME/.config/hypr/scripts/system-update.sh\""];
        updateProcess.running = true;
    }
    function toggleCalendarFromBar() { shellRoot.coordinator.toggle("calendar", monitorName, clockGeometry); }
    function toggleNotificationsFromBar() { shellRoot.coordinator.toggle("notifications", monitorName, notificationChipGeometry); }
    function toggleQuickSettingsFromBar(sourceItem, section) { shellRoot.coordinator.toggle("quick-settings", monitorName, chipRect(sourceItem || rightZone), section || ""); }
    function toggleMediaFromBar() { shellRoot.coordinator.toggle("media", monitorName, mediaChipGeometry); }

    // Sync helper
    function syncActive() { return transfer.hasActiveTransfers || syncthing.syncing; }
    function syncWarning() { return syncthing.hasErrors || (!syncthing.serviceActive && !syncthing.apiReachable); }

    // Media label
    function mediaLabel() {
        if (media.status !== "available" || !media.active || !media.title) return "";
        var a = media.artists && media.artists.length ? " — " + media.artists.join(", ") : "";
        return media.title + a;
    }

    // ── Three-zone RowLayout ──
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.outerMargin
        anchors.rightMargin: root.outerMargin
        spacing: root.groupGap

        // ── LEFT ZONE: Workspace cluster + Health capsule ──
        RowLayout {
            id: leftZone
            Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
            spacing: root.groupGap

            // Workspace cluster (scrollable)
            Flickable {
                id: workspaceScroller
                Layout.minimumWidth: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                Layout.preferredWidth: Math.max(Theme.Tokens.scaled(Theme.Tokens.heightChip), Math.min(wsCluster.implicitWidth, Theme.Tokens.scaled(360)))
                Layout.maximumWidth: Theme.Tokens.scaled(360)
                Layout.preferredHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                Layout.alignment: Qt.AlignVCenter
                clip: true
                interactive: contentWidth > width
                contentWidth: wsCluster.implicitWidth
                contentHeight: height
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                pressDelay: 80

                RowLayout {
                    id: wsCluster
                    spacing: root.innerGap
                    height: workspaceScroller.height

                    Repeater {
                        model: root.workspaceEntries
                        delegate: wsPillDelegate
                    }
                }
            }

            // Health capsule: CPU + RAM + Temp in one pill
            HealthCapsule {
                id: healthCapsule
                systemModel: root.systemModel
                Layout.alignment: Qt.AlignVCenter
                onOpenSystem: root.toggleQuickSettingsFromBar(healthCapsule, "system")
                onHoveredChanged: {
                    if (!root.islandHost) return;
                    root.islandHost.sourceHoverChanged("health", hovered);
                }
            }

            FocusScope {
                id: leftUpdatePill
                property bool ho: false
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.max(Theme.Tokens.scaled(Theme.Tokens.heightChip), leftUpdateRow.implicitWidth + root.capsulePadH * 2)
                implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: !root.updates.checked ? "Checking for updates" : root.updates.count > 0 ? root.updates.count + " updates available" : "System up to date"
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: root.updateLaunchState === "failed" ? Theme.Tokens.glass(Theme.Tokens.stateDanger, 0.34) : leftUpdatePill.ho ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62) }
                RowLayout {
                    id: leftUpdateRow
                    anchors.centerIn: parent
                    spacing: root.innerGap
                    Text { text: root.updateLaunchState === "failed" ? "\uF071" : !root.updates.checked ? "\uF021" : root.updates.count > 0 ? "\uF019" : "\uF00C"; color: root.updateLaunchState === "failed" ? Theme.Tokens.stateDanger : root.updates.count > 0 ? Theme.Tokens.stateInfo : Theme.Tokens.textMuted; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconXs }
                    Text { visible: !root.updates.checked || root.updates.count > 0 || root.updateLaunchState === "failed"; text: root.updateLaunchState === "failed" ? "!" : !root.updates.checked ? "…" : String(root.updates.count); color: root.updateLaunchState === "failed" ? Theme.Tokens.stateDanger : Theme.Tokens.textPrimary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall; font.bold: true }
                }
                HoverHandler { onHoveredChanged: { leftUpdatePill.ho = hovered; if (root.islandHost) root.islandHost.sourceHoverChanged("updates", hovered); } }
                TapHandler { onTapped: root.runSystemUpdate() }
                TapHandler { acceptedButtons: Qt.RightButton; onTapped: root.updates.refresh() }
            }
        }

        // Center spacer — takes all available space so right zone is right-aligned
        Item { Layout.fillWidth: true; Layout.minimumWidth: Theme.Tokens.scaled(20) }

        // ── RIGHT ZONE: Connectivity | AudioPower | Notifications | Updates ──
        RowLayout {
            id: rightZone
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            spacing: root.groupGap

            // Connectivity capsule (WiFi + VPN + Bluetooth)
            ConnectivityCapsule {
                id: connectivityCapsule
                network: root.network
                bluetooth: root.bluetooth
                Layout.alignment: Qt.AlignVCenter
                onOpenNetwork: root.toggleQuickSettingsFromBar(connectivityCapsule, "network")
                onHoveredChanged: {
                    if (!root.islandHost) return;
                    root.islandHost.sourceHoverChanged("connectivity", hovered);
                }
            }

            // Audio + Power capsule
            AudioPowerCapsule {
                id: audioPowerCapsule
                audio: root.audio
                battery: root.battery
                Layout.alignment: Qt.AlignVCenter
                onToggleMute: root.toggleMute()
                onAdjustVolume: function(delta) { root.adjustVolume(delta); }
                onOpenPower: root.toggleQuickSettingsFromBar(audioPowerCapsule, "battery")
                onHoveredChanged: {
                    if (!root.islandHost) return;
                    root.islandHost.sourceHoverChanged("audio-power", hovered);
                }
            }

            // Notification pill
            FocusScope {
                id: notifPill
                property bool ho: false
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.max(Theme.Tokens.scaled(Theme.Tokens.heightChip), notifRow.implicitWidth + root.capsulePadH * 2)
                implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: root.showNotificationBadge ? root.notificationModel.notifications.length + " notifications" : "No notifications"
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.Tokens.radiusPill
                    color: notifPill.ho
                        ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78)
                        : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62)
                }
                RowLayout {
                    id: notifRow
                    anchors.centerIn: parent
                    spacing: root.innerGap
                    Text {
                        text: root.notificationModel && root.notificationModel.dnd ? "\uF1F6" : root.showNotificationBadge ? "\uF0F3" : "\uF0A2"
                        color: root.notificationModel && root.notificationModel.dnd ? Theme.Tokens.stateWarning : root.showNotificationBadge ? Theme.Tokens.stateInfo : Theme.Tokens.textMuted
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: Theme.Tokens.iconSm
                    }
                    Text {
                        visible: root.showNotificationBadge
                        text: root.notificationModel && root.notificationModel.notifications ? String(root.notificationModel.notifications.length) : ""
                        color: Theme.Tokens.stateInfo
                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                        font.family: Theme.Tokens.typographyFontFamily
                        font.bold: true
                    }
                }
                HoverHandler { onHoveredChanged: { notifPill.ho = hovered; if (root.islandHost) root.islandHost.sourceHoverChanged("notification-preview", hovered); } }
                TapHandler { onTapped: root.toggleNotificationsFromBar() }
                Keys.onReturnPressed: root.toggleNotificationsFromBar()
                Keys.onSpacePressed: root.toggleNotificationsFromBar()
            }

            // Sync: only visible when active or unhealthy
            FocusScope {
                id: syncPill
                property bool ho: false
                property bool pr: false
                visible: syncActive() || syncWarning()
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.max(Theme.Tokens.scaled(Theme.Tokens.heightChip), syncRow.implicitWidth + root.capsulePadH * 2)
                implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Sync"
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.Tokens.radiusPill
                    color: syncPill.pr
                        ? Theme.Tokens.tonalPrimaryContainer
                        : syncPill.ho
                            ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.80)
                            : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.66)
                }
                RowLayout {
                    id: syncRow
                    anchors.centerIn: parent
                    spacing: root.innerGap
                    Text {
                        text: "\uF2EF"
                        color: syncWarning() ? Theme.Tokens.stateWarning : syncActive() ? Theme.Tokens.stateInfo : Theme.Tokens.textSecondary
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: Theme.Tokens.iconSm
                    }
                    Text {
                        text: "Sync"
                        color: Theme.Tokens.textSecondary
                        font.pixelSize: Theme.Tokens.typographyLabelMedium
                        font.family: Theme.Tokens.typographyFontFamily
                    }
                    Rectangle {
                        width: 6; height: 6; radius: 3
                        color: syncWarning() ? Theme.Tokens.stateWarning : syncActive() ? Theme.Tokens.stateInfo : Theme.Tokens.stateSuccess
                        SequentialAnimation on opacity {
                            running: syncActive() && !Theme.Tokens.reducedMotion
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 600 }
                            NumberAnimation { to: 1; duration: 600 }
                        }
                    }
                }
                HoverHandler { onHoveredChanged: { syncPill.ho = hovered; if (root.islandHost) root.islandHost.sourceHoverChanged("sync", hovered); } }
                TapHandler {
                    onPressedChanged: syncPill.pr = pressed
                    onTapped: {
                        shellRoot.coordinator.toggle("sync", monitorName, root.syncGeometry);
                        syncPill.forceActiveFocus();
                    }
                }
                Keys.onReturnPressed: shellRoot.coordinator.toggle("sync", monitorName, root.syncGeometry)
                Keys.onSpacePressed: shellRoot.coordinator.toggle("sync", monitorName, root.syncGeometry)
            }

            // Package updates pill
            FocusScope {
                id: updatePill
                property bool ho: false
                visible: false
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Math.max(Theme.Tokens.scaled(58), updateRow.implicitWidth + Theme.Tokens.scaled(18))
                implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                Layout.minimumWidth: Theme.Tokens.scaled(58)
                Layout.preferredWidth: Math.max(Theme.Tokens.scaled(58), implicitWidth)
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: {
                    if (root.updateLaunchState === "failed") return "Update terminal failed to open";
                    if (root.updateLaunchState === "opening") return "Opening update terminal";
                    if (!updates.checked) return "Checking for system updates";
                    if (updates.count > 0) return updates.count + " updates available";
                    return "System up to date";
                }
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.Tokens.radiusPill
                    color: root.updateLaunchState === "failed"
                        ? Theme.Tokens.glass(Theme.Tokens.stateDanger, 0.34)
                        : updatePill.ho
                            ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78)
                            : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62)
                }
                RowLayout {
                    id: updateRow
                    anchors.centerIn: parent
                    spacing: root.innerGap
                    Text {
                        text: {
                            if (root.updateLaunchState === "failed") return "\uF071";
                            if (root.updateLaunchState === "opening") return "\uF021";
                            if (!updates.checked) return "\uF021";
                            if (updates.count > 0) return "\uF019";
                            return "\uF00C";
                        }
                        color: {
                            if (root.updateLaunchState === "failed") return Theme.Tokens.stateDanger;
                            if (!updates.checked) return Theme.Tokens.textMuted;
                            if (updates.count > 0) return Theme.Tokens.stateInfo;
                            return Theme.Tokens.textMuted;
                        }
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: Theme.Tokens.iconSm
                    }
                    Text {
                        text: {
                            if (root.updateLaunchState === "failed") return "UP !";
                            if (root.updateLaunchState === "opening") return "UP …";
                            if (!updates.checked) return "UP …";
                            return "UP " + String(updates.count);
                        }
                        color: {
                            if (root.updateLaunchState === "failed") return Theme.Tokens.stateDanger;
                            if (updates.count > 0) return Theme.Tokens.textPrimary;
                            return Theme.Tokens.textMuted;
                        }
                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                        font.family: Theme.Tokens.typographyFontFamily
                        font.bold: updates.count > 0 || root.updateLaunchState === "failed"
                    }
                }
                HoverHandler { onHoveredChanged: { updatePill.ho = hovered; if (root.islandHost) root.islandHost.sourceHoverChanged("updates", hovered); } }
                TapHandler { onTapped: root.runSystemUpdate() }
                TapHandler { acceptedButtons: Qt.RightButton; onTapped: updates.refresh() }
                Keys.onReturnPressed: root.runSystemUpdate()
                Keys.onSpacePressed: root.runSystemUpdate()
                Tooltip {
                    target: updatePill
                    text: root.updateLaunchMessage !== ""
                        ? root.updateLaunchMessage
                        : !updates.checked
                            ? "Checking for updates…"
                            : updates.tooltip !== ""
                                ? updates.tooltip + " · click to update, right-click to refresh"
                                : "Click to update · right-click to refresh"
                }
            }

            // Provider health dot
            Rectangle {
                visible: root.providerDegraded
                width: Theme.Tokens.scaled(8)
                height: Theme.Tokens.scaled(8)
                radius: Theme.Tokens.scaled(4)
                color: Theme.Tokens.stateWarning
                Layout.alignment: Qt.AlignVCenter
                HoverHandler { onHoveredChanged: { if (root.islandHost) root.islandHost.sourceHoverChanged("provider-health", hovered); } }
            }
        }
    }

    // ── Workspace pill delegate ──
    Component {
        id: wsPillDelegate
        FocusScope {
            id: wsb
            required property string modelData
            property bool ho: false
            property bool pr: false
            property bool hovered: ho
            property bool active: root.monitorActiveWS() === modelData
            property bool occupied: root.wsOccupied(modelData)
            property bool urg: root.wsUrgent(modelData)
            property bool hasActiveWindow: active && root.activeWindowMatches(modelData)
            property string activeApp: hasActiveWindow ? WorkspacePresentation.applicationName(root.hyprland.activeWindow) : ""
            property string activeTitle: hasActiveWindow ? WorkspacePresentation.windowTitle(root.hyprland.activeWindow) : ""

            implicitWidth: Math.max(Theme.Tokens.scaled(Theme.Tokens.heightChip), pillRow.implicitWidth + Theme.Tokens.scaled(14))
            implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: WorkspacePresentation.tooltip(modelData, active, occupied, activeApp, activeTitle)

            Rectangle {
                anchors.fill: parent
                radius: Theme.Tokens.radiusPill
                color: {
                    if (pr) return Theme.Tokens.tonalPrimaryContainer;
                    if (active) return Theme.Tokens.tonalPrimary;
                    if (ho) return Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78);
                    return Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62);
                }
                border.color: active ? Theme.Tokens.tonalPrimary : activeFocus ? Theme.Tokens.outlineFocus : "transparent"
                border.width: active ? 1 : activeFocus ? 2 : 0
                opacity: active ? 1.0 : occupied ? 0.85 : 0.55
            }

            RowLayout {
                id: pillRow
                anchors.centerIn: parent
                spacing: Theme.Tokens.scaled(5)
                Text {
                    text: modelData
                    color: active ? Theme.Tokens.tonalOnPrimary : occupied ? Theme.Tokens.textPrimary : Theme.Tokens.textMuted
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyLabelMedium
                    font.bold: active
                }
                Text {
                    visible: hasActiveWindow
                    text: "\uF2D2"
                    color: Theme.Tokens.tonalOnPrimary
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                }
                Text {
                    visible: hasActiveWindow && activeApp !== ""
                    text: activeApp
                    color: Theme.Tokens.tonalOnPrimary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.maximumWidth: Theme.Tokens.scaled(96)
                }
            }

            // Urgent dot
            Rectangle {
                visible: urg
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 1
                width: 6; height: 6; radius: 3
                color: Theme.Tokens.stateDanger
            }

            HoverHandler { onHoveredChanged: { wsb.ho = hovered; if (root.islandHost) root.islandHost.sourceHoverChanged("workspace", hovered); } }
            TapHandler {
                onPressedChanged: wsb.pr = pressed
                onTapped: {
                    wsb.forceActiveFocus();
                    root.focusWS(modelData);
                }
            }
            WheelHandler { onWheel: function(e) { root.cycleWS(e.angleDelta.y > 0 ? -1 : 1); e.accepted = true; } }
            Keys.onReturnPressed: root.focusWS(modelData)
            Keys.onLeftPressed: root.cycleWS(-1)
            Keys.onRightPressed: root.cycleWS(1)

            Tooltip {
                target: wsb
                text: WorkspacePresentation.tooltip(modelData, active, occupied, activeApp, activeTitle)
            }
        }
    }

    // activeWindowMatches helper
    function activeWindowMatches(name) {
        return WorkspacePresentation.activeWindowMatches(name, monitorName, hyprland.focusedMonitor,
            hyprland.activeWorkspace, hyprland.activeWindow);
    }
}
