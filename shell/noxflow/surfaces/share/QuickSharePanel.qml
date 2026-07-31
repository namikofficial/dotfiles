// QuickSharePanel — left-side activity panel for nearby file sharing (SUPER+S).
//
// Left-anchored layer surface. Coexists with right-side island states
// (design contract §3.2). Shows:
//   - daemon health (LocalSend reachable? alias?)
//   - send entry point (opens the LocalSend app, which owns discovery,
//     pairing, accept/decline, and progress)
//   - truthful transfer history (intents recorded, never faked progress)
//
// The actual transfer engine is the LocalSend app; this panel is the launch
// point + status surface (design contract §7, execution rule: no fake data).

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
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
    implicitWidth: Theme.Tokens.scaled(340)
    implicitHeight: Math.min(Theme.Tokens.scaled(520), root.screen ? root.screen.height - margins.top - Theme.Tokens.scaled(24) : Theme.Tokens.scaled(520))
    exclusiveZone: 0; aboveWindows: true; focusable: true; color: "transparent"
    visible: lifecycle.active

    Connections {
        target: lifecycle
        function onOpened() { root.transfer.checkDaemon(); root.transfer.refreshing = true; }
        function onClosed() { root.transfer.refreshing = false; }
    }
    Component.onDestruction: root.transfer.refreshing = false

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
                    Components.IconButton { iconText: "\uF00D"; accessibleName: "Close quick share"; onClicked: lifecycle.requestClose("closeButton") }
                }

                // Daemon status card
                Rectangle {
                    Layout.fillWidth: true
                    radius: Theme.Tokens.radiusMd
                    color: transfer.daemonUp ? Theme.Tokens.withAlpha(Theme.Tokens.stateSuccess, 0.12)
                        : Theme.Tokens.withAlpha(Theme.Tokens.stateWarning, 0.10)
                    border.color: transfer.daemonUp ? Theme.Tokens.withAlpha(Theme.Tokens.stateSuccess, 0.4)
                        : Theme.Tokens.withAlpha(Theme.Tokens.stateWarning, 0.4)
                    border.width: 1
                    implicitHeight: Theme.Tokens.scaled(64)
                    RowLayout { anchors.fill: parent; anchors.margins: Theme.Tokens.spacingMd; spacing: Theme.Tokens.spacingMd
                        Text { text: transfer.daemonUp ? "\uF0A1" : "\uF071"
                            color: transfer.daemonUp ? Theme.Tokens.stateSuccess : Theme.Tokens.stateWarning
                            font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconMd }
                        ColumnLayout { Layout.fillWidth: true; spacing: 2
                            Text { text: transfer.daemonUp ? (transfer.daemonAlias || "LocalSend") : "LocalSend not running"
                                color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: transfer.daemonUp ? "Nearby sharing ready" : (transfer.daemonError || "Start LocalSend to share files")
                                color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        Components.IconButton { iconText: "\uF021"; accessibleName: "Refresh status"; onClicked: transfer.checkDaemon() }
                    }
                }

                // Primary action: send
                Components.TextButton {
                    Layout.fillWidth: true
                    text: "Share files…"
                    onClicked: {
                        transfer.launchApp();
                        transfer.recordSendIntent();
                    }
                }

                // Hint
                Text { text: "Discovery, accept/decline, and progress are handled by the LocalSend app. Your phone's Quick Share pairs via LocalSend's own flow."
                    color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall
                    wrapMode: Text.Wrap; Layout.fillWidth: true }

                // History
                Text { text: "Recent activity"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyTitleMedium
                    Layout.topMargin: Theme.Tokens.spacingSm; visible: transfer.history.length > 0 }
                ListView {
                    id: list
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true
                    model: transfer.history
                    spacing: Theme.Tokens.spacingXs
                    visible: transfer.history.length > 0
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        required property var modelData
                        width: list.width; height: Theme.Tokens.scaled(44)
                        radius: Theme.Tokens.radiusMd
                        color: Theme.Tokens.withAlpha(Theme.Tokens.surfaceSurfaceHighest, 0.3)
                        RowLayout { anchors.fill: parent; anchors.margins: Theme.Tokens.spacingMd; spacing: Theme.Tokens.spacingMd
                            Text { text: modelData.action === "send" ? "\uF064" : "\uF059"
                                color: Theme.Tokens.tonalPrimary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconSm }
                            ColumnLayout { Layout.fillWidth: true; spacing: 2
                                Text { text: modelData.action === "send" ? "Send initiated" : "LocalSend opened"
                                    color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodySmall; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: root.timeLabel(modelData.createdAt); color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                            }
                            Text { text: modelData.state; color: Theme.Tokens.stateInfo; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                        }
                    }
                }
                Text { text: "No recent activity"; color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyBodySmall
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter; visible: transfer.history.length === 0
                    Layout.topMargin: Theme.Tokens.spacingXl }
            }
        }
    }

    function timeLabel(ts) {
        if (!ts) return "";
        var d = new Date(ts);
        return d.toLocaleTimeString(Qt.locale(), "HH:mm");
    }

    function toggle() { lifecycle.toggle(); }
    function open() { lifecycle.open(); }
    function close() { lifecycle.requestClose("close"); }
}
