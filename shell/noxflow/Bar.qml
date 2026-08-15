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
    required property var noxd; required property var hyprland; required property var audio
    required property var battery; required property var network; required property var bluetooth
    required property var media; required property var notificationModel; required property var systemModel
    required property var transfer; required property var syncthing
    required property var updates
    property bool showNotificationBadge: !!(notificationModel && notificationModel.notifications && notificationModel.notifications.length > 0)
    property string monitorName: screen && screen.name ? screen.name : ""
    // Explicitly refreshed when noxd publishes a Hyprland snapshot. A binding
    // to a JavaScript function was unreliable here because nested array
    // changes did not always invalidate the delegate model.
    property var workspaceEntries: []
    property var monitor: findMonitor()
    property bool providerDegraded: hasDegradedProvider()
    property bool urgent: monitorUrgentCount() > 0
    property string pendingWorkspace: ""
    property Process workspaceDispatch: Process {
        running: false
        onExited: function(code) {
            if (code !== 0) root.pendingWorkspace = "";
            else workspacePendingTimer.restart();
        }
    }
    Timer { id: workspacePendingTimer; interval: 1200; onTriggered: root.pendingWorkspace = "" }
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

    readonly property bool reducedMotion: Theme.Tokens.reducedMotion
    readonly property real pillHeight: Theme.Tokens.scaled(32)

    function chipRect(item) { if (!item || !item.visible) return Qt.rect(0,0,0,0); var p = item.mapToItem(null,0,0); return Qt.rect(p.x,p.y,item.width,item.height); }
    readonly property rect clockGeometry: Qt.rect(0, 0, 0, 0)
    readonly property rect mediaChipGeometry: chipRect(mediaPill)
    readonly property rect notificationChipGeometry: chipRect(notifPill)
    readonly property rect statusClusterGeometry: chipRect(statusCluster)
    readonly property rect networkGeometry: chipRect(netPill)
    readonly property rect bluetoothGeometry: chipRect(btPill)
    readonly property rect volumeGeometry: chipRect(volPill)
    readonly property rect batteryGeometry: chipRect(batPill)
    readonly property rect syncGeometry: chipRect(syncPill)

    function registerMorphChips() {
        var reg = shellRoot.triggerRegistry;
        if (!reg) return;
        reg.registerTrigger("calendar", monitorName, clockGeometry, Theme.Tokens.radiusPill);
        reg.registerTrigger("media", monitorName, mediaChipGeometry, Theme.Tokens.radiusPill);
        reg.registerTrigger("notifications", monitorName, notificationChipGeometry, Theme.Tokens.radiusPill);
        reg.registerTrigger("quick-settings", monitorName, volumeGeometry, Theme.Tokens.radiusPill);
        reg.registerTrigger("quick-settings", monitorName, networkGeometry, Theme.Tokens.radiusPill, "network");
        reg.registerTrigger("quick-settings", monitorName, bluetoothGeometry, Theme.Tokens.radiusPill, "bluetooth");
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

    function objVal(o,a,b,f) { if (o&&o[a]!==undefined&&o[a]!==null) return o[a]; if (o&&b&&o[b]!==undefined&&o[b]!==null) return o[b]; return f; }
    function wsId(v) { return WorkspacePresentation.workspaceId(v); }
    function monitorId() { return monitor && monitor.id !== undefined ? Number(monitor.id) : -1; }
    function findMonitor() { for (var i=0;i<hyprland.monitors.length;i++) if (String(hyprland.monitors[i].name||"")===monitorName) return hyprland.monitors[i]; return null; }
    function buildWorkspaceEntries() {
        // Workspaces are sourced from both workspace records and clients.
        // The client pass matters for minimized/hidden windows and for the
        // brief interval where Hyprland has published clients first.
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
        // Keep the focused workspace visible even when it is empty.
        var active = monitorActiveWS();
        if (active !== "" && e.indexOf(active) < 0) e.push(active);
        // Numeric workspaces first (1, 2, 3…), named ones after.
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
    function wsRecord(name) { for (var i=0;i<hyprland.workspaces.length;i++) { var it=hyprland.workspaces[i]; if (String(it.name||it.id)===name&&String(it.monitor||"")===monitorName) return it; } return null; }
    function monitorActiveWS() {
        if (pendingWorkspace !== "") return pendingWorkspace;
        if (hyprland.focusedMonitor === monitorName && hyprland.activeWorkspace)
            return wsId(hyprland.activeWorkspace);
        return wsId(monitor ? objVal(monitor, "activeWorkspace", "active_workspace", null) : null);
    }

    function activeWindowMatches(name) {
        return WorkspacePresentation.activeWindowMatches(name, monitorName, hyprland.focusedMonitor,
            hyprland.activeWorkspace, hyprland.activeWindow);
    }

    function wsOccupied(name) { for (var i=0;i<hyprland.windows.length;i++) { var w=hyprland.windows[i]; var ws=w.workspace; if (ws&&wsId(ws)===name&&wsRecord(name)) return true; } return false; }
    function monitorUrgentCount() { var c=0; for (var i=0;i<hyprland.windows.length;i++) { var w=hyprland.windows[i]; if (hyprland.urgentWindows.indexOf(String(w.address||""))>=0&&wsRecord(wsId(w.workspace))) c++; } return c; }
    function wsUrgent(name) { for (var i=0;i<hyprland.windows.length;i++) { var w=hyprland.windows[i]; if (wsId(w.workspace)===name&&hyprland.urgentWindows.indexOf(String(w.address||""))>=0&&wsRecord(name)) return true; } return false; }
    function hasDegradedProvider() { var ss=noxd.providerHealth||{}; for (var p in ss) if (ss[p]==="degraded") return true; return false; }
    function focusWS(name) {
        var target = String(name || "").trim();
        if (!target || target.indexOf("special:") === 0 || !/^[0-9A-Za-z_-]+$/.test(target)) return;
        pendingWorkspace = target;
        refreshWorkspaceEntries();
        // Hyprland 0.56 exposes dispatchers through `eval`; `hyprctl dispatch`
        // now parses its arguments as Lua and rejects the legacy form.
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
    function toggleMute() { noxd.runAction({audio_toggle_mute:{target:"output"}}); }
    function runSystemUpdate() {
        // Keep one update path for Wayle and NoxFlow. The wrapper selects
        // paru/yay/pacman, chooses an available terminal, logs the invocation,
        // and falls back to a direct update when no terminal is available.
        if (updateProcess.running) return;
        updateLaunchState = "opening";
        updateLaunchMessage = "Opening update terminal…";
        updateProcess.command = ["sh", "-lc", "exec \"$HOME/.config/hypr/scripts/system-update.sh\""];
        updateProcess.running = true;
    }
    function refreshNet() { noxd.runAction({network_refresh:{}}); }
    function toggleBT() { noxd.runAction({bluetooth_set_powered:{powered:!bluetooth.powered}}); }
    function toggleMedia() { noxd.runAction({media_play_pause:{}}); }
    function toggleCalendarFromBar() { shellRoot.coordinator.toggle("calendar", monitorName, clockGeometry); }
    function toggleNotificationsFromBar() { shellRoot.coordinator.toggle("notifications", monitorName, notificationChipGeometry); }
    function toggleQuickSettingsFromBar(sourceItem, section) { shellRoot.coordinator.toggle("quick-settings", monitorName, chipRect(sourceItem || statusCluster), section || ""); }
    function openSystemFromPill(sourceItem) {
        sourceItem.forceActiveFocus();
        toggleQuickSettingsFromBar(sourceItem, "system");
    }
    function gibibytes(kibibytes) { return (Number(kibibytes || 0) / 1024 / 1024).toFixed(1) + " GiB"; }
    function activeWinLabel() { var w=hyprland.activeWindow; if (!w||typeof w!=="object") return ""; return String(w.title||w.application_id||w.class||w.appid||"").trim(); }
    function mediaLabel() { if (media.status!=="available"||!media.active||!media.title) return ""; var a=media.artists&&media.artists.length?" — "+media.artists.join(", "):""; return media.title+a; }
    function netLabel() { if (network.status!=="available") return ""; if (network.connectivity==="full"||network.connectivity==="limited") return network.connectedSsid||"Network"; if (network.ethernet&&network.ethernet.length) return "Ethernet"; return "Offline"; }
    function btLabel() { if (bluetooth.status!=="available"||!bluetooth.adapterPresent) return ""; for (var i=0;i<bluetooth.devices.length;i++) if (bluetooth.devices[i].connected===true) return bluetooth.devices[i].name||"Bluetooth"; return bluetooth.powered?"Bluetooth":""; }
    function syncActive() { return transfer.hasActiveTransfers || syncthing.syncing; }
    function syncWarning() { return syncthing.hasErrors || (!syncthing.serviceActive && !syncthing.apiReachable); }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
        anchors.rightMargin: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
        spacing: Theme.Tokens.scaled(6)

        // Left: workspaces followed by passive system-stat pills. The
        // workspace strip stays bounded and scrolls instead of painting over
        // the fixed stat/media/status groups on narrow monitors.
        Flickable {
            id: workspaceScroller
            Layout.minimumWidth: Theme.Tokens.scaled(56)
            Layout.preferredWidth: Math.max(Theme.Tokens.scaled(56), Math.min(wsCluster.implicitWidth, Theme.Tokens.scaled(360)))
            Layout.maximumWidth: Theme.Tokens.scaled(360)
            Layout.preferredHeight: root.pillHeight
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
                spacing: Theme.Tokens.scaled(4)
                height: workspaceScroller.height
                Repeater {
                    model: root.workspaceEntries
                    delegate: FocusScope {
                    id: wsb; required property string modelData; required property int index
                    property bool ho: false; property bool pr: false; property bool hovered: ho
                    property bool active: root.monitorActiveWS() === modelData
                    property bool occupied: root.wsOccupied(modelData)
                    property bool urg: root.wsUrgent(modelData)
                    property bool hasActiveWindow: active && root.activeWindowMatches(modelData)
                    property string activeApp: hasActiveWindow ? WorkspacePresentation.applicationName(root.hyprland.activeWindow) : ""
                    property string activeTitle: hasActiveWindow ? WorkspacePresentation.windowTitle(root.hyprland.activeWindow) : ""
                    implicitWidth: Math.max(root.pillHeight, wsRow.implicitWidth + Theme.Tokens.scaled(14))
                    implicitHeight: root.pillHeight
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: WorkspacePresentation.tooltip(modelData, active, occupied, activeApp, activeTitle)

                    // Pill background (always visible — no outer bar needed)
                    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill
                        color: wsb.pr ? Theme.Tokens.tonalPrimaryContainer : wsb.active ? Theme.Tokens.tonalPrimary : wsb.ho ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62)
                        border.color: wsb.active ? Theme.Tokens.tonalPrimary : wsb.activeFocus ? Theme.Tokens.outlineFocus : "transparent"; border.width: wsb.active ? 1 : wsb.activeFocus ? 2 : 0
                        opacity: wsb.active ? 1.0 : wsb.occupied ? 0.85 : 0.55
                    }
                    RowLayout { id: wsRow; anchors.centerIn: parent; spacing: Theme.Tokens.scaled(5)
                        Text { id: wlbl; text: modelData
                            color: wsb.active ? Theme.Tokens.tonalOnPrimary : wsb.occupied ? Theme.Tokens.textPrimary : Theme.Tokens.textMuted
                            font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelMedium; font.bold: wsb.active }
                        Text { visible: wsb.hasActiveWindow; text: "\uF2D2"; color: Theme.Tokens.tonalOnPrimary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                        Text { visible: wsb.hasActiveWindow && wsb.activeApp !== ""; text: wsb.activeApp; color: Theme.Tokens.tonalOnPrimary
                            font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall; font.bold: true
                            elide: Text.ElideRight; Layout.maximumWidth: Theme.Tokens.scaled(96) }
                    }
                    Rectangle { visible: wsb.urg; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 1; width: 6; height: 6; radius: 3; color: Theme.Tokens.stateDanger }
                    HoverHandler { onHoveredChanged: wsb.ho = hovered }
                    TapHandler { onPressedChanged: wsb.pr = pressed; onTapped: { wsb.forceActiveFocus(); root.focusWS(modelData); } }
                    WheelHandler { onWheel: function(e) { root.cycleWS(e.angleDelta.y > 0 ? -1 : 1); e.accepted = true; } }
                    Keys.onReturnPressed: root.focusWS(modelData)
                    Keys.onLeftPressed: root.cycleWS(-1)
                    Keys.onRightPressed: root.cycleWS(1)
                    Behavior on implicitWidth { enabled: !root.reducedMotion; NumberAnimation { duration: Theme.Tokens.durationShort; easing.type: Easing.OutCubic } }
                    Tooltip { target: wsb; text: WorkspacePresentation.tooltip(modelData, active, occupied, activeApp, activeTitle) }
                    }
                }
            }
        }

        // Passive system telemetry. Values come from the shared SystemModel
        // so every monitor instance displays the same sampled host state.
        RowLayout {
            id: systemStatsCluster
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.Tokens.scaled(4)

            FocusScope {
                id: cpuPill
                property bool ho: false
                property bool hovered: ho
                readonly property bool ready: !!root.systemModel && root.systemModel.ready
                readonly property string value: ready ? Math.round(root.systemModel.cpuUsage) + "%" : "--"
                implicitWidth: Math.max(root.pillHeight, cpuRow.implicitWidth + Theme.Tokens.scaled(14))
                implicitHeight: root.pillHeight
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "CPU usage: " + value
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill
                    color: cpuPill.ho ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62)
                }
                RowLayout { id: cpuRow; anchors.centerIn: parent; spacing: 4
                    Text { text: "\uF2DB"; color: cpuPill.ready && root.systemModel.cpuUsage > 80 ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    Text { text: cpuPill.value; color: cpuPill.ready && root.systemModel.cpuUsage > 80 ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                }
                HoverHandler { onHoveredChanged: cpuPill.ho = hovered }
                TapHandler { onTapped: root.openSystemFromPill(cpuPill) }
                Keys.onReturnPressed: root.openSystemFromPill(cpuPill)
                Keys.onSpacePressed: root.openSystemFromPill(cpuPill)
                Tooltip { target: cpuPill; text: cpuPill.ready ? "CPU usage: " + cpuPill.value : "CPU usage unavailable" }
            }

            FocusScope {
                id: ramPill
                property bool ho: false
                property bool hovered: ho
                readonly property bool ready: !!root.systemModel && root.systemModel.ready && root.systemModel.memTotal > 0
                readonly property string value: ready ? Math.round(root.systemModel.memPercent) + "%" : "--"
                implicitWidth: Math.max(root.pillHeight, ramRow.implicitWidth + Theme.Tokens.scaled(14))
                implicitHeight: root.pillHeight
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "RAM usage: " + value
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill
                    color: ramPill.ho ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62)
                }
                RowLayout { id: ramRow; anchors.centerIn: parent; spacing: 4
                    Text { text: "\uF538"; color: ramPill.ready && root.systemModel.memPercent > 80 ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    Text { text: ramPill.value; color: ramPill.ready && root.systemModel.memPercent > 80 ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                }
                HoverHandler { onHoveredChanged: ramPill.ho = hovered }
                TapHandler { onTapped: root.openSystemFromPill(ramPill) }
                Keys.onReturnPressed: root.openSystemFromPill(ramPill)
                Keys.onSpacePressed: root.openSystemFromPill(ramPill)
                Tooltip {
                    target: ramPill
                    text: ramPill.ready ? "RAM: " + root.gibibytes(root.systemModel.memUsed) + " used of " + root.gibibytes(root.systemModel.memTotal) + " (" + ramPill.value + ")" : "RAM usage unavailable"
                }
            }

            FocusScope {
                id: tempPill
                property bool ho: false
                property bool hovered: ho
                readonly property bool ready: !!root.systemModel && root.systemModel.ready && root.systemModel.cpuTemp > 0
                readonly property string value: ready ? Math.round(root.systemModel.cpuTemp) + "°C" : "--"
                implicitWidth: Math.max(root.pillHeight, tempRow.implicitWidth + Theme.Tokens.scaled(14))
                implicitHeight: root.pillHeight
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Temperature: " + value
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill
                    color: tempPill.ho ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62)
                }
                RowLayout { id: tempRow; anchors.centerIn: parent; spacing: 4
                    Text { text: "\uF2C9"; color: tempPill.ready && root.systemModel.cpuTemp > 80 ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    Text { text: tempPill.value; color: tempPill.ready && root.systemModel.cpuTemp > 80 ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                }
                HoverHandler { onHoveredChanged: tempPill.ho = hovered }
                TapHandler { onTapped: root.openSystemFromPill(tempPill) }
                Keys.onReturnPressed: root.openSystemFromPill(tempPill)
                Keys.onSpacePressed: root.openSystemFromPill(tempPill)
                Tooltip { target: tempPill; text: tempPill.ready ? "Highest host temperature: " + tempPill.value : "Temperature unavailable" }
            }
        }

        // Keep media and status controls grouped at the far right after the
        // workspace/stat region has taken only the width it needs.
        Item { Layout.fillWidth: true }

        // Active window label (fades into the bar, low opacity)
        // The active-window title belongs in the expanded island. Keeping it
        // out of the transparent rail prevents long titles from colliding
        // with workspace chips or the centered island.

        // Media pill
        FocusScope {
            id: mediaPill; property bool ho: false; property bool pr: false
            visible: mediaText.text !== ""
            implicitWidth: Math.max(pillHeight, mediaRow.implicitWidth + Theme.Tokens.scaled(14))
            implicitHeight: pillHeight
            Layout.maximumWidth: Theme.Tokens.scaled(240)
            activeFocusOnTab: true
            Accessible.name: mediaText.text !== "" ? "Media: " + mediaText.text : ""
            Accessible.role: Accessible.Button
            Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill
                color: mediaPill.pr ? Theme.Tokens.tonalSecondaryContainer : mediaPill.ho ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62) }
            RowLayout { id: mediaRow; anchors.centerIn: parent; spacing: 4
                Text { text: "\uF001"; color: Theme.Tokens.tonalSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                Text { id: mediaText; Layout.maximumWidth: Theme.Tokens.scaled(220); elide: Text.ElideRight; text: root.mediaLabel(); color: Theme.Tokens.tonalSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
            }
            HoverHandler { onHoveredChanged: mediaPill.ho = hovered }
            TapHandler { onPressedChanged: mediaPill.pr = pressed; onTapped: { shellRoot.coordinator.toggle("media", monitorName, root.mediaChipGeometry); mediaPill.forceActiveFocus(); } }
        }

        // Right status cluster
        RowLayout { id: statusCluster; Layout.alignment: Qt.AlignRight; spacing: Theme.Tokens.scaled(4)

            // Network pill
            FocusScope { id: netPill; property bool ho: false; visible: root.netLabel() !== ""
                implicitWidth: Math.max(pillHeight, netRow.implicitWidth + Theme.Tokens.scaled(14)); implicitHeight: pillHeight
                activeFocusOnTab: true; Accessible.name: "Network: " + root.netLabel()
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: netPill.ho ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62) }
                RowLayout { id: netRow; anchors.centerIn: parent; spacing: 4
                    Text { text: "\uF1EB"; color: Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    Text { text: root.netLabel(); color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall; elide: Text.ElideRight }
                }
                HoverHandler { onHoveredChanged: netPill.ho = hovered }
                TapHandler { onTapped: { root.toggleQuickSettingsFromBar(netPill, "network"); netPill.forceActiveFocus(); } }
            }

            // Bluetooth pill
            FocusScope { id: btPill; property bool ho: false; visible: root.btLabel() !== ""
                implicitWidth: Math.max(pillHeight, btRow.implicitWidth + Theme.Tokens.scaled(14)); implicitHeight: pillHeight
                activeFocusOnTab: true; Accessible.name: "Bluetooth: " + root.btLabel()
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: btPill.ho ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62) }
                RowLayout { id: btRow; anchors.centerIn: parent; spacing: 4
                    Text { text: "\uF294"; color: Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    Text { text: root.btLabel(); color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                }
                HoverHandler { onHoveredChanged: btPill.ho = hovered }
                TapHandler { onTapped: { root.toggleQuickSettingsFromBar(btPill, "bluetooth"); btPill.forceActiveFocus(); } }
            }

            // Volume pill
            FocusScope { id: volPill; property bool ho: false; visible: audio.status === "available"
                implicitWidth: Math.max(pillHeight, volRow.implicitWidth + Theme.Tokens.scaled(14)); implicitHeight: pillHeight
                activeFocusOnTab: true; Accessible.name: "Volume: " + (audio.outputMuted ? "muted" : audio.outputVolumePercent + " percent")
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: volPill.ho ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62) }
                RowLayout { id: volRow; anchors.centerIn: parent; spacing: 4
                    Text { text: audio.outputMuted ? "\uF026" : "\uF028"; color: audio.outputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    Text { text: audio.outputVolumePercent + "%"; color: audio.outputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall; visible: !audio.outputMuted }
                }
                HoverHandler { onHoveredChanged: volPill.ho = hovered }
                TapHandler { onTapped: { root.toggleQuickSettingsFromBar(volPill, "volume"); volPill.forceActiveFocus(); } }
            }

            // Battery pill
            FocusScope { id: batPill; property bool ho: false; visible: battery.status === "available" && battery.present && battery.percentage !== null
                implicitWidth: Math.max(pillHeight, batRow.implicitWidth + Theme.Tokens.scaled(14)); implicitHeight: pillHeight
                activeFocusOnTab: true; Accessible.name: "Battery: " + Math.round(battery.percentage) + "%"
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: batPill.ho ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62) }
                RowLayout { id: batRow; anchors.centerIn: parent; spacing: 4
                    Text { text: battery.charging ? "\uF1E6" : battery.critical ? "\uF244" : "\uF240"; color: battery.critical ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    Text { text: Math.round(battery.percentage) + "%"; color: battery.critical ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                }
                HoverHandler { onHoveredChanged: batPill.ho = hovered }
                TapHandler { onTapped: root.toggleQuickSettingsFromBar(batPill, "battery") }
            }

            // Sync belongs with the right-side status controls. Keeping it out
            // of the flexible middle region prevents it from drifting or
            // colliding with the active-window label and centered clock.
            FocusScope {
                id: syncPill; property bool ho: false; property bool pr: false
                implicitWidth: Math.max(pillHeight, syncRow.implicitWidth + Theme.Tokens.scaled(14)); implicitHeight: pillHeight
                activeFocusOnTab: true; Accessible.role: Accessible.Button; Accessible.name: "Sync"
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: syncPill.pr ? Theme.Tokens.tonalPrimaryContainer : syncPill.ho ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.80) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.66) }
                RowLayout { id: syncRow; anchors.centerIn: parent; spacing: 4
                    Text { text: "⇄"; color: root.syncWarning() ? Theme.Tokens.stateWarning : root.syncActive() ? Theme.Tokens.stateInfo : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    Text { text: "Sync"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: root.syncWarning() ? Theme.Tokens.stateWarning : root.syncActive() ? Theme.Tokens.stateInfo : Theme.Tokens.stateSuccess
                        SequentialAnimation on opacity {
                            running: root.syncActive() && !Theme.Tokens.reducedMotion
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 600 }
                            NumberAnimation { to: 1; duration: 600 }
                        }
                    }
                }
                HoverHandler { onHoveredChanged: syncPill.ho = hovered }
                TapHandler { onPressedChanged: syncPill.pr = pressed; onTapped: { shellRoot.coordinator.toggle("sync", monitorName, root.syncGeometry); syncPill.forceActiveFocus(); } }
            }

            // Package updates (same source as the Wayle fallback shell).
            // Left-click opens the updater; right-click re-checks.
            FocusScope { id: updatePill; property bool ho: false; property bool hovered: ho
                // Keep the affordance visible during the first asynchronous
                // poll; disappearing status controls make the bar feel broken.
                visible: true
                implicitWidth: Math.max(Theme.Tokens.scaled(58), updateRow.implicitWidth + Theme.Tokens.scaled(18)); implicitHeight: pillHeight
                Layout.minimumWidth: Theme.Tokens.scaled(58); Layout.preferredWidth: Math.max(Theme.Tokens.scaled(58), implicitWidth)
                activeFocusOnTab: true; Accessible.role: Accessible.Button
                Accessible.name: root.updateLaunchState === "failed" ? "Update terminal failed to open" : root.updateLaunchState === "opening" ? "Opening update terminal" : !updates.checked ? "Checking for system updates" : updates.count > 0 ? updates.count + " updates available" : "System up to date"
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: root.updateLaunchState === "failed" ? Theme.Tokens.glass(Theme.Tokens.stateDanger, 0.34) : updatePill.ho ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62) }
                RowLayout { id: updateRow; anchors.centerIn: parent; spacing: 4
                    Text { text: root.updateLaunchState === "failed" ? "\uF071" : root.updateLaunchState === "opening" ? "\uF021" : !updates.checked ? "\uF021" : updates.count > 0 ? "\uF019" : "\uF00C"; color: root.updateLaunchState === "failed" ? Theme.Tokens.stateDanger : !updates.checked ? Theme.Tokens.textMuted : updates.count > 0 ? Theme.Tokens.stateInfo : Theme.Tokens.textMuted; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    Text { text: root.updateLaunchState === "failed" ? "UP !" : root.updateLaunchState === "opening" ? "UP …" : !updates.checked ? "UP …" : "UP " + String(updates.count); color: root.updateLaunchState === "failed" ? Theme.Tokens.stateDanger : updates.count > 0 ? Theme.Tokens.textPrimary : Theme.Tokens.textMuted; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall; font.bold: updates.count > 0 || root.updateLaunchState === "failed" }
                }
                HoverHandler { onHoveredChanged: updatePill.ho = hovered }
                TapHandler { onTapped: root.runSystemUpdate() }
                TapHandler { acceptedButtons: Qt.RightButton; onTapped: updates.refresh() }
                Tooltip { target: updatePill; text: root.updateLaunchMessage !== "" ? root.updateLaunchMessage : !updates.checked ? "Checking for updates…" : updates.tooltip !== "" ? updates.tooltip + " · click to update, right-click to refresh" : "Click to update · right-click to refresh" }
            }

            // Notification pill
            FocusScope { id: notifPill; property bool ho: false
                implicitWidth: Math.max(pillHeight, notifR.implicitWidth + Theme.Tokens.scaled(14)); implicitHeight: pillHeight
                activeFocusOnTab: true; Accessible.role: Accessible.Button
                Accessible.name: root.showNotificationBadge ? root.notificationModel.notifications.length + " notifications" : "No notifications"
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: notifPill.ho ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62) }
                RowLayout { id: notifR; anchors.centerIn: parent; spacing: 4
                    Text { text: root.showNotificationBadge ? "\uF0F3" : "\uF0A2"; color: root.showNotificationBadge ? Theme.Tokens.stateInfo : Theme.Tokens.textMuted; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    Text { visible: root.showNotificationBadge; text: root.notificationModel && root.notificationModel.notifications ? String(root.notificationModel.notifications.length) : ""; color: Theme.Tokens.stateInfo; font.pixelSize: Theme.Tokens.typographyLabelSmall; font.bold: true }
                }
                HoverHandler { onHoveredChanged: notifPill.ho = hovered }
                TapHandler { onTapped: root.toggleNotificationsFromBar() }
            }

            // Health dot
            Rectangle { visible: root.providerDegraded; width: Theme.Tokens.scaled(8); height: Theme.Tokens.scaled(8); radius: Theme.Tokens.scaled(4); color: Theme.Tokens.stateWarning; HoverHandler {} }
        }
    }

}
