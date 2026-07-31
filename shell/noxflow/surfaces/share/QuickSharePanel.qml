// QuickSharePanel — left-side activity panel for nearby file sharing (SUPER+S).
//
// Full custom UI backed by the noxd 'transfer' provider (LocalSend v2):
//   - live device list (discovered via multicast)
//   - inline file picker (xdg-desktop-portal) + send with progress
//   - transfer cards with per-file progress, accept/decline/cancel/retry
//   - completed-transfer history + daemon status
// No external app is launched for transfers.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../../theme" as Theme
import "../../components" as Components

PanelWindow {
    id: root
    property var screen
    required property var noxd
    required property var transfer

    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    Behavior on openProgress { NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType } }

    // Left-anchored panel below the bar.
    screen: root.screen
    anchors.left: true; anchors.top: true
    margins.left: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
    margins.top: Theme.Tokens.scaled(Theme.Tokens.heightToolbar + Theme.Tokens.spacingSm)
    implicitWidth: Theme.Tokens.scaled(360)
    implicitHeight: Math.min(Theme.Tokens.scaled(560), root.screen ? root.screen.height - margins.top - Theme.Tokens.scaled(24) : Theme.Tokens.scaled(560))
    exclusiveZone: 0; aboveWindows: true; focusable: true; color: "transparent"
    visible: lifecycle.active

    property string pickedFiles: ""
    property string pickBuffer: ""
    property bool picking: false
    property int selectedDeviceIndex: -1

    // ── Daemon health probe ──
    property bool daemonUp: false
    property string daemonAlias: "NoxFlow"
    property bool daemonChecked: false
    property Process probeProc: Process {
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) { root._onProbe(data); }
        }
    }

    function checkDaemon() {
        probeProc.command = ["curl", "-sk", "--max-time", "2", "https://127.0.0.1:53317/api/localsend/v2/info"];
        probeProc.running = true;
    }
    function _onProbe(data) {
        var out = data || "";
        daemonUp = out.trim() !== "";
        daemonChecked = true;
        if (daemonUp) {
            try {
                var info = JSON.parse(out);
                daemonAlias = info.alias || "NoxFlow";
            } catch (e) {}
        }
    }

    Connections {
        target: lifecycle
        function onOpened() {
            root.checkDaemon();
            root.transfer.refreshing = true;
        }
        function onClosed() { root.transfer.refreshing = false; }
    }
    Component.onDestruction: root.transfer.refreshing = false

    // Incoming request notification
    Connections {
        target: root.transfer
        function onIncomingRequested(session) {
            var names = session.files ? session.files.map(function(f) { return f.name; }).join(", ") : "files";
            if (root.noxd && root.noxd.connected) root.noxd.runAction({ notify_show: { summary: "Incoming share from " + (session.peer_alias || "peer"), body: names } });
        }
    }

    FocusScope {
        id: focusRoot; focus: lifecycle.interactive; anchors.fill: parent
        Keys.onEscapePressed: lifecycle.requestClose("escape")

        Rectangle {
            anchors.fill: parent; radius: Theme.Tokens.radiusXl
            color: Theme.Tokens.surfaceSurfaceContainerHigh
            border.color: Theme.Tokens.outlineDefault; border.width: 1
            opacity: root.openProgress; scale: 0.9 + 0.1 * root.openProgress
            transformOrigin: Item.TopLeft

            ColumnLayout {
                anchors.fill: parent; anchors.margins: Theme.Tokens.spacingLg
                spacing: Theme.Tokens.spacingMd

                // Header
                RowLayout { Layout.fillWidth: true
                    Text { text: "Quick Share"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyTitleLarge; font.bold: true; Layout.fillWidth: true }
                    Components.IconButton { iconText: "\uF021"; accessibleName: "Rescan devices"; onClicked: root.transfer.discover() }
                    Components.IconButton { iconText: "\uF00D"; accessibleName: "Close quick share"; onClicked: lifecycle.requestClose("closeButton") }
                }

                Flickable {
                    id: contentFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    contentHeight: contentColumn.height
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    ColumnLayout {
                        id: contentColumn
                        width: contentFlick.width
                        spacing: Theme.Tokens.spacingMd

                        // Daemon status line
                        Text { text: root.daemonStatusText(); color: root.daemonUp ? Theme.Tokens.stateSuccess : Theme.Tokens.stateWarning
                            font.pixelSize: Theme.Tokens.typographyLabelSmall; Layout.fillWidth: true; elide: Text.ElideRight }

                // ── Active incoming (accept/decline) ──
                Text { text: "Incoming"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyTitleMedium
                    visible: root.transfer.pendingIncoming.length > 0; Layout.topMargin: Theme.Tokens.spacingSm }
                Repeater {
                    model: root.transfer.pendingIncoming
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property var s: modelData
                        Layout.fillWidth: true
                        radius: Theme.Tokens.radiusMd
                        color: Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceHighest, 0.3)
                        implicitHeight: Theme.Tokens.scaled(84)
                        ColumnLayout { anchors.fill: parent; anchors.margins: Theme.Tokens.spacingMd; spacing: Theme.Tokens.spacingXs
                            Text { text: s.peer_alias + " wants to send " + s.files.length + " file(s)"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: root.filesSummary(s.files); color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                            RowLayout { Layout.fillWidth: true; spacing: Theme.Tokens.spacingSm
                                Components.TextButton { text: "Accept"; Layout.fillWidth: true; onClicked: root.transfer.accept(s.id) }
                                Components.TextButton { text: "Decline"; Layout.fillWidth: true; onClicked: root.transfer.decline(s.id) }
                            }
                        }
                    }
                }

                // ── Active transfers (progress) ──
                Text { text: "Transfers"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyTitleMedium
                    visible: root.transfer.activeTransfers.length > 0; Layout.topMargin: Theme.Tokens.spacingSm }
                Repeater {
                    model: root.transfer.activeTransfers
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property var s: modelData
                        Layout.fillWidth: true
                        radius: Theme.Tokens.radiusMd
                        color: Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceHighest, 0.3)
                        implicitHeight: Theme.Tokens.scaled(78)
                        ColumnLayout { anchors.fill: parent; anchors.margins: Theme.Tokens.spacingMd; spacing: Theme.Tokens.spacingXs
                            Text { text: (s.direction === "out" ? "To " : "From ") + s.peer_alias; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            // Read-only progress bar
                            Rectangle { Layout.fillWidth: true; height: 4; radius: 2; color: Theme.Tokens.outlineSubtle
                                Rectangle { width: Math.max(0, parent.width * root.sessionProgress(s)); height: 4; radius: 2; color: Theme.Tokens.tonalPrimary } }
                            RowLayout { Layout.fillWidth: true
                                Text { text: root.progressText(s); color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall; Layout.fillWidth: true }
                                Components.IconButton { iconText: "\uF05E"; accessibleName: "Cancel transfer"; visible: s.state === "transferring" || s.state === "offered" || s.state === "incoming"
                                    onClicked: root.transfer.cancel(s.id) }
                            }
                        }
                    }
                }

                // ── Failed (retry) ──
                Repeater {
                    model: root.transfer.sessions.filter(function(s) { return s.state === "failed" || s.state === "cancelled" || s.state === "declined"; })
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property var s: modelData
                        Layout.fillWidth: true
                        radius: Theme.Tokens.radiusMd
                        color: Theme.Tokens.withAlpha(Theme.Tokens.stateWarning, 0.10)
                        implicitHeight: Theme.Tokens.scaled(56)
                        RowLayout { anchors.fill: parent; anchors.margins: Theme.Tokens.spacingMd; spacing: Theme.Tokens.spacingMd
                            Text { text: s.state.toUpperCase(); color: Theme.Tokens.stateWarning; font.pixelSize: Theme.Tokens.typographyLabelSmall; font.bold: true }
                            Text { text: s.error || ("Transfer " + s.state); color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                    }
                }

                // ── Devices + send ──
                Text { text: "Nearby devices"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyTitleMedium
                    Layout.topMargin: Theme.Tokens.spacingSm; visible: root.transfer.devices.length > 0 }
                ListView {
                    id: deviceList
                    Layout.fillWidth: true; Layout.preferredHeight: Math.min(Theme.Tokens.scaled(132), root.transfer.devices.length * Theme.Tokens.scaled(52))
                    clip: true
                    model: root.transfer.devices
                    boundsBehavior: Flickable.StopAtBounds
                    spacing: Theme.Tokens.spacingXs
                    visible: root.transfer.devices.length > 0
                    onCountChanged: {
                        if (root.selectedDeviceIndex < 0 && count > 0) root.selectedDeviceIndex = 0;
                        else if (root.selectedDeviceIndex >= count) root.selectedDeviceIndex = count - 1;
                    }

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property var d: modelData
                        width: deviceList.width; height: Theme.Tokens.scaled(48)
                        radius: Theme.Tokens.radiusMd
                        color: root.selectedDeviceIndex === index ? Theme.Tokens.surfaceSurfaceHighest : "transparent"
                        border.color: root.selectedDeviceIndex === index ? Theme.Tokens.outlineSubtle : "transparent"
                        border.width: 1

                        RowLayout { anchors.fill: parent; anchors.margins: Theme.Tokens.spacingMd; spacing: Theme.Tokens.spacingMd
                            Text { text: root.deviceIcon(d.device_type); color: Theme.Tokens.tonalPrimary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconMd }
                            ColumnLayout { Layout.fillWidth: true; spacing: 2
                                Text { text: d.alias; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: d.ip; color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                            }
                            Text { text: "Ready"; color: Theme.Tokens.stateSuccess; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                        }
                        TapHandler { onTapped: root.selectedDeviceIndex = index }
                        HoverHandler { onHoveredChanged: { if (hovered) root.selectedDeviceIndex = index; } cursorShape: Qt.PointingHandCursor }
                    }
                }
                Text { text: root.transfer.devices.length === 0 ? "No devices found. Make sure LocalSend/Quick Share is open on the other device." : ""
                    color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall; wrapMode: Text.Wrap; Layout.fillWidth: true }

                // Send button
                Components.TextButton {
                    Layout.fillWidth: true
                    text: "Send files…"
                    enabled: root.transfer.devices.length > 0 && !root.picking
                    onClicked: root.pickAndSend()
                }

                // ── History ──
                Text { text: "Recent"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyTitleMedium
                    visible: root.transfer.sessions.length > 0; Layout.topMargin: Theme.Tokens.spacingSm }
                Repeater {
                    model: root.transfer.sessions.filter(function(s) { return s.state === "completed"; })
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property var s: modelData
                        Layout.fillWidth: true
                        radius: Theme.Tokens.radiusMd
                        color: Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceHighest, 0.2)
                        implicitHeight: Theme.Tokens.scaled(40)
                        RowLayout { anchors.fill: parent; anchors.margins: Theme.Tokens.spacingMd; spacing: Theme.Tokens.spacingMd
                            Text { text: s.direction === "out" ? "\uF064" : "\uF078"; color: Theme.Tokens.tonalPrimary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconSm }
                            Text { text: (s.direction === "out" ? "Sent to " : "Received from ") + s.peer_alias; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodySmall; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                    }
                }
                    Text { text: root.transfer.sessions.length === 0 ? "No transfers yet" : ""; color: Theme.Tokens.textMuted
                        font.pixelSize: Theme.Tokens.typographyBodySmall; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
                    
                    // Keep the Flickable content bounded when the panel is empty.
                    Item { Layout.fillHeight: true; Layout.minimumHeight: 1 }
                }
            }
        }
    }
    }

    // ── Helpers ──
    function daemonStatusText() {
        if (!daemonChecked) return "Checking sharing service…";
        return daemonUp ? "Sharing ready — receiving on port 53317" : "Sharing service not reachable";
    }
    function filesSummary(files) {
        if (!files || files.length === 0) return "";
        var total = files.reduce(function(a, f) { return a + (f.size || 0); }, 0);
        return files.length + " file(s) · " + root.humanSize(total);
    }
    function sessionProgress(s) {
        if (!s || !s.files || s.files.length === 0) return 0;
        var total = s.files.reduce(function(a, f) { return a + (f.size || 0); }, 0);
        var done = s.files.reduce(function(a, f) { return a + (f.transferred || 0); }, 0);
        return total > 0 ? done / total : 0;
    }
    function progressText(s) {
        var pct = Math.round(root.sessionProgress(s) * 100);
        return root.humanSize(s.files ? s.files.reduce(function(a, f) { return a + (f.transferred || 0); }, 0) : 0) + " / " +
            root.humanSize(s.files ? s.files.reduce(function(a, f) { return a + (f.size || 0); }, 0) : 0) + " (" + pct + "%)";
    }
    function humanSize(bytes) {
        if (!bytes) return "0 B";
        var units = ["B", "KB", "MB", "GB"];
        var i = 0;
        while (bytes >= 1024 && i < units.length - 1) { bytes /= 1024; i++; }
        return bytes.toFixed(i > 0 ? 1 : 0) + " " + units[i];
    }
    function deviceIcon(type) {
        switch (type) {
            case "mobile": return "\uF10B";
            case "web": return "\uF108";
            default: return "\uF109";
        }
    }

    // File picker via xdg-desktop-portal (GTK/zenity fallback). No shell.
    property Process pickProc: Process {
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) { root.pickBuffer += (data || "") + "\n"; }
        }
        onExited: root._finishPicking()
    }
    function pickAndSend() {
        if (root.picking || root.selectedDeviceIndex < 0) return;
        root.picking = true;
        root.pickBuffer = "";
        pickProc.command = ["sh", "-c",
            "XDG_CURRENT_DESKTOP=hyprland GTK_USE_PORTAL=1 zenity --file-selection --multiple --separator='\\n' 2>/dev/null || " +
            "gtk-file-chooser 2>/dev/null || echo __CANCELLED__"];
        pickProc.running = true;
    }
    function _finishPicking() {
        root.picking = false;
        var text = (root.pickBuffer || "").trim();
        root.pickBuffer = "";
        if (!text || text === "__CANCELLED__") return;
        var paths = text.split("\n").filter(function(p) { return p.trim() !== ""; });
        if (paths.length > 0 && root.selectedDeviceIndex >= 0 && root.selectedDeviceIndex < root.transfer.devices.length) {
            var peer = root.transfer.devices[root.selectedDeviceIndex];
            root.transfer.send(peer.id, paths);
        }
    }

    function toggle() { lifecycle.toggle(); }
    function open() { lifecycle.open(); }
    function close() { lifecycle.requestClose("close"); }
}
