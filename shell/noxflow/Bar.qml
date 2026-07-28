import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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
    property Process workspaceDispatch: Process { running: false }
    property string compositorWorkspace: ""
    property Process workspaceProbe: Process {
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                try {
                    var state = JSON.parse(String(data).trim());
                    if (state && state.name !== undefined) {
                        root.compositorWorkspace = String(state.name);
                    }
                } catch (error) {}
            }
        }
    }
    readonly property bool reducedMotion: Theme.Tokens.reducedMotion
    readonly property real pillHeight: Theme.Tokens.scaled(32)

    function chipRect(item) { if (!item || !item.visible) return Qt.rect(0,0,0,0); var p = item.mapToItem(null,0,0); return Qt.rect(p.x,p.y,item.width,item.height); }
    readonly property rect clockGeometry: chipRect(clockPill)
    readonly property rect mediaChipGeometry: chipRect(mediaPill)
    readonly property rect notificationChipGeometry: chipRect(notifPill)
    readonly property rect statusClusterGeometry: chipRect(statusCluster)
    readonly property rect networkGeometry: chipRect(netPill)
    readonly property rect bluetoothGeometry: chipRect(btPill)
    readonly property rect volumeGeometry: chipRect(volPill)
    readonly property rect batteryGeometry: chipRect(batPill)

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
    }
    Timer { interval: 250; repeat: true; running: root.visible; onTriggered: root.registerMorphChips() }
    Timer {
        interval: 120
        repeat: true
        running: root.visible
        onTriggered: {
            if (!workspaceProbe.running) {
                workspaceProbe.command = ["sh", "-c", "hyprctl activeworkspace -j | jq -c ."];
                workspaceProbe.running = true;
            }
        }
    }
    Component.onCompleted: registerMorphChips()

    screen: root.screen
    anchors.top: true; anchors.left: true; anchors.right: true
    exclusiveZone: Theme.Tokens.scaled(Theme.Tokens.heightToolbar)
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightToolbar)
    color: "transparent"

    function objVal(o,a,b,f) { if (o&&o[a]!==undefined&&o[a]!==null) return o[a]; if (o&&b&&o[b]!==undefined&&o[b]!==null) return o[b]; return f; }
    function wsId(v) { if (v&&typeof v==="object") return objVal(v,"id","name",""); return v===undefined||v===null?"":String(v); }
    function findMonitor() { for (var i=0;i<hyprland.monitors.length;i++) if (String(hyprland.monitors[i].name||"")===monitorName) return hyprland.monitors[i]; return null; }
    function buildWorkspaceEntries() { var e=[]; for (var i=1;i<=10;i++) e.push(String(i)); for (var j=0;j<hyprland.workspaces.length;j++) { var n=String(hyprland.workspaces[j].name||""); if (n&&n.indexOf("special:")!==0&&e.indexOf(n)<0) e.push(n); } return e; }
    function wsRecord(name) { for (var i=0;i<hyprland.workspaces.length;i++) { var it=hyprland.workspaces[i]; if (String(it.name||it.id)===name&&String(it.monitor||"")===monitorName) return it; } return null; }
    function monitorActiveWS() {
        // Hyprland emits workspace/focusedmon events with the new active
        // workspace, while the monitor list is refreshed less often. Prefer
        // that event-backed value for the focused monitor so keyboard and
        // compositor-driven changes repaint the indicator immediately.
        if (Quickshell.activeScreen && Quickshell.activeScreen.name === monitorName && hyprland.activeWorkspace)
            return wsId(hyprland.activeWorkspace);
        return wsId(monitor ? objVal(monitor, "activeWorkspace", "active_workspace", null) : null);
    }
    function displayedActiveWS() {
        if (Quickshell.activeScreen && Quickshell.activeScreen.name === monitorName && compositorWorkspace !== "")
            return compositorWorkspace;
        return monitorActiveWS();
    }
    function wsOccupied(name) { for (var i=0;i<hyprland.windows.length;i++) { var w=hyprland.windows[i]; var ws=w.workspace; if (ws&&wsId(ws)===name&&wsRecord(name)) return true; } return false; }
    function monitorUrgentCount() { var c=0; for (var i=0;i<hyprland.windows.length;i++) { var w=hyprland.windows[i]; if (hyprland.urgentWindows.indexOf(String(w.address||""))>=0&&wsRecord(wsId(w.workspace))) c++; } return c; }
    function wsUrgent(name) { for (var i=0;i<hyprland.windows.length;i++) { var w=hyprland.windows[i]; if (wsId(w.workspace)===name&&hyprland.urgentWindows.indexOf(String(w.address||""))>=0&&wsRecord(name)) return true; } return false; }
    function hasDegradedProvider() { var ss=noxd.providerHealth||{}; for (var p in ss) if (ss[p]==="degraded") return true; return false; }
    function focusWS(name) {
        var target = String(name || "").trim();
        if (!target || target.indexOf("special:") === 0 || !/^[0-9A-Za-z_-]+$/.test(target)) return;
        // Workspace focus is a compositor dispatch, not a provider action. Use
        // Hyprland's IPC directly so a slow/degraded noxd cannot swallow a click.
        workspaceDispatch.running = false;
        workspaceDispatch.command = ["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + target + "\" })"];
        workspaceDispatch.running = true;
    }
    function cycleWS(d) {
        var direction = d < 0 ? "e-1" : "e+1";
        workspaceDispatch.running = false;
        workspaceDispatch.command = ["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + direction + "\" })"];
        workspaceDispatch.running = true;
    }
    function toggleMute() { noxd.runAction({audio_toggle_mute:{target:"output"}}); }
    function refreshNet() { noxd.runAction({network_refresh:{}}); }
    function toggleBT() { noxd.runAction({bluetooth_set_powered:{powered:!bluetooth.powered}}); }
    function toggleMedia() { noxd.runAction({media_play_pause:{}}); }
    function toggleCalendarFromBar() { shellRoot.coordinator.toggle("calendar", monitorName, clockGeometry); }
    function toggleNotificationsFromBar() { shellRoot.coordinator.toggle("notifications", monitorName, notificationChipGeometry); }
    function toggleQuickSettingsFromBar(sourceItem, section) { shellRoot.coordinator.toggle("quick-settings", monitorName, chipRect(sourceItem || statusCluster), section || ""); }
    function activeWinLabel() { var w=hyprland.activeWindow; if (!w||typeof w!=="object") return ""; return String(w.title||w.application_id||w.class||w.appid||"").trim(); }
    function mediaLabel() { if (media.status!=="available"||!media.active||!media.title) return ""; var a=media.artists&&media.artists.length?" — "+media.artists.join(", "):""; return media.title+a; }
    function netLabel() { if (network.status!=="available") return ""; if (network.connectivity==="full"||network.connectivity==="limited") return network.connectedSsid||"Network"; if (network.ethernet&&network.ethernet.length) return "Ethernet"; return "Offline"; }
    function btLabel() { if (bluetooth.status!=="available"||!bluetooth.adapterPresent) return ""; for (var i=0;i<bluetooth.devices.length;i++) if (bluetooth.devices[i].connected===true) return bluetooth.devices[i].name||"Bluetooth"; return bluetooth.powered?"Bluetooth":""; }

    // ── Main layout: background is transparent, chips float as individual pills ──
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
        anchors.rightMargin: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
        spacing: Theme.Tokens.scaled(6)

        // Left: workspaces
        RowLayout { id: wsCluster; spacing: Theme.Tokens.scaled(4)
            Repeater {
                model: root.workspaceEntries
                delegate: FocusScope {
                    id: wsb; required property string modelData; required property int index
                    property bool ho: false; property bool pr: false
                    property bool active: (root.compositorWorkspace !== "" ? root.compositorWorkspace : root.monitorActiveWS()) === modelData
                    property bool occupied: root.wsOccupied(modelData)
                    property bool urg: root.wsUrgent(modelData)
                    implicitWidth: Math.max(pillHeight, wlbl.implicitWidth + Theme.Tokens.scaled(14))
                    implicitHeight: pillHeight
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Workspace " + modelData + (active ? ", active" : occupied ? ", occupied" : "")

                    // Pill background (always visible — no outer bar needed)
                    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill
                        color: wsb.pr ? Theme.Tokens.tonalPrimaryContainer : wsb.active ? "#8FA8FF" : wsb.ho ? Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceHighest, 0.6) : Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceContainerHigh, 0.4)
                        border.color: wsb.active ? Theme.Tokens.tonalPrimary : wsb.activeFocus ? Theme.Tokens.outlineFocus : "transparent"; border.width: wsb.active ? 1 : wsb.activeFocus ? 2 : 0
                        opacity: wsb.active ? 1.0 : wsb.occupied ? 0.85 : 0.55
                    }
                    Text { id: wlbl; anchors.centerIn: parent; text: modelData
                        color: wsb.active ? "#101A3A" : wsb.occupied ? Theme.Tokens.textPrimary : Theme.Tokens.textMuted
                        font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelMedium; font.bold: wsb.active }
                    Rectangle { visible: wsb.urg; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 1; width: 6; height: 6; radius: 3; color: Theme.Tokens.stateDanger }
                    HoverHandler { onHoveredChanged: wsb.ho = hovered }
                    TapHandler { onPressedChanged: wsb.pr = pressed; onTapped: { wsb.forceActiveFocus(); root.focusWS(modelData); } }
                    WheelHandler { onWheel: function(e) { root.cycleWS(e.angleDelta.y > 0 ? -1 : 1); e.accepted = true; } }
                    Keys.onReturnPressed: root.focusWS(modelData)
                    Keys.onLeftPressed: root.cycleWS(-1)
                    Keys.onRightPressed: root.cycleWS(1)
                }
            }
        }

        // Active window label (fades into the bar, low opacity)
        Text {
            Layout.fillWidth: true; Layout.minimumWidth: Theme.Tokens.scaled(40)
            Layout.maximumWidth: Theme.Tokens.scaled(200)
            elide: Text.ElideRight; text: root.activeWinLabel()
            color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyBodySmall
        }

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
                color: mediaPill.pr ? Theme.Tokens.tonalSecondaryContainer : mediaPill.ho ? Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceHighest, 0.6) : Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceContainerHigh, 0.4) }
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
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: netPill.ho ? Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceHighest, 0.6) : Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceContainerHigh, 0.4) }
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
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: btPill.ho ? Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceHighest, 0.6) : Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceContainerHigh, 0.4) }
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
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: volPill.ho ? Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceHighest, 0.6) : Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceContainerHigh, 0.4) }
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
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: batPill.ho ? Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceHighest, 0.6) : Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceContainerHigh, 0.4) }
                RowLayout { id: batRow; anchors.centerIn: parent; spacing: 4
                    Text { text: battery.charging ? "\uF1E6" : battery.critical ? "\uF244" : "\uF240"; color: battery.critical ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    Text { text: Math.round(battery.percentage) + "%"; color: battery.critical ? Theme.Tokens.stateDanger : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                }
                HoverHandler { onHoveredChanged: batPill.ho = hovered }
                TapHandler { onTapped: root.toggleQuickSettingsFromBar(batPill, "battery") }
            }

            // Notification pill
            FocusScope { id: notifPill; property bool ho: false
                implicitWidth: Math.max(pillHeight, notifR.implicitWidth + Theme.Tokens.scaled(14)); implicitHeight: pillHeight
                activeFocusOnTab: true; Accessible.role: Accessible.Button
                Accessible.name: root.showNotificationBadge ? root.notificationModel.notifications.length + " notifications" : "No notifications"
                Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: notifPill.ho ? Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceHighest, 0.6) : Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceContainerHigh, 0.4) }
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

    // Clock pill (centered on top of the RowLayout via z-index)
    FocusScope {
        id: clockPill; anchors.centerIn: parent; z: 10; property bool ho: false
        implicitWidth: Math.max(Theme.Tokens.scaled(60), cText.implicitWidth + Theme.Tokens.scaled(20))
        implicitHeight: Theme.Tokens.scaled(34)
        activeFocusOnTab: true; Accessible.name: "Current time: " + cText.text
        Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill
            color: clockPill.ho ? Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceHighest, 0.7) : Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceContainerHigh, 0.5) }
        Text { id: cText; anchors.centerIn: parent; text: Qt.formatTime(new Date(), "HH:mm")
            color: Theme.Tokens.textPrimary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyTitleMedium; font.bold: true
            Timer { interval: 1000; repeat: true; running: true; onTriggered: cText.text = Qt.formatTime(new Date(), "HH:mm") }
        }
        HoverHandler { onHoveredChanged: clockPill.ho = hovered }
        TapHandler { onTapped: root.toggleCalendarFromBar() }
    }


}
