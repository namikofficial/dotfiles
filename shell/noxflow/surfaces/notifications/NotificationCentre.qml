// NotificationCentre — notification history & management panel.
// Stolen from: DankMaterialShell + Tide notification surface.
// Opened with Super + N (or from island / bar).
// Groups by app, supports DND, history, clear all, inline actions.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme" as Theme
import "../../components" as Components

PanelWindow {
    id: root

    required property var noxd
    required property var notifModel   // NotificationModel instance
    required property var morphRegistry

    /// Current animation phase
    property real openProgress: 0
    property bool panelOpen: false
    property bool showHistory: false

    anchors.top: true
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    exclusiveZone: 0
    aboveWindows: true
    focusable: true
    color: "transparent"
    visible: panelOpen

    Behavior on width {
        NumberAnimation { duration: Theme.Tokens.duration(250); easing.type: Easing.OutCubic }
    }

    // ── Scrim ──
    Rectangle {
        anchors.fill: parent
        color: Theme.Tokens.withAlpha(Theme.Tokens.tonalBackground, 0.5)
        opacity: root.openProgress * 0.8
        visible: root.openProgress > 0
        Behavior on opacity { NumberAnimation { duration: Theme.Tokens.duration(200) } }
        TapHandler { onTapped: root.close() }
    }

    // ── Panel background ──
    Rectangle {
        anchors.fill: parent
        radius: Theme.Tokens.radiusXl
        color: Theme.Tokens.surfaceSurfaceContainerHigh
        border.color: Theme.Tokens.outlineDefault
        border.width: 1
        opacity: root.openProgress
        scale: 0.85 + 0.15 * root.openProgress
        Behavior on scale {
            NumberAnimation { duration: Theme.Tokens.duration(200); easing.type: Easing.OutBack }
        }
        Behavior on opacity {
            NumberAnimation { duration: Theme.Tokens.duration(150) }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.Tokens.spacingLg
            spacing: Theme.Tokens.spacingMd

            // ── Header ──
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.showHistory ? "History" : "Notifications"
                    color: Theme.Tokens.textPrimary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyTitleLarge
                    font.bold: true
                    Layout.fillWidth: true
                }

                // Clear all
                Text {
                    text: "Clear"
                    color: Theme.Tokens.stateInfo
                    font.pixelSize: Theme.Tokens.typographyLabelMedium
                    visible: !root.showHistory && notifModel.notifications.length > 0
                    TapHandler { onTapped: notifModel.clearAll() }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }

                Components.IconButton {
                    iconText: "✕"
                    accessibleName: "Close notifications"
                    onClicked: root.close()
                }
            }

            // ── DND toggle row ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.Tokens.spacingMd
                visible: !root.showHistory
                Text {
                    text: "Do Not Disturb"
                    color: Theme.Tokens.textPrimary
                    font.pixelSize: Theme.Tokens.typographyBodyMedium
                    Layout.fillWidth: true
                }
                Components.Toggle {
                    checked: notifModel.dnd
                    onToggled: notifModel.toggleDnd()
                }
            }

            Components.Divider { Layout.fillWidth: true }

            // ── Tab picker: active / history ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.Tokens.spacingXs
                Rectangle {
                    Layout.fillWidth: true
                    height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                    radius: Theme.Tokens.radiusPill
                    color: !root.showHistory ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                    border.color: !root.showHistory ? Theme.Tokens.tonalPrimary : "transparent"
                    border.width: !root.showHistory ? 1 : 0
                    Text {
                        anchors.centerIn: parent
                        text: "Active (" + notifModel.notifications.length + ")"
                        color: !root.showHistory ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                        font.pixelSize: Theme.Tokens.typographyLabelMedium
                    }
                    TapHandler { onTapped: root.showHistory = false }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                    radius: Theme.Tokens.radiusPill
                    color: root.showHistory ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                    border.color: root.showHistory ? Theme.Tokens.tonalPrimary : "transparent"
                    border.width: root.showHistory ? 1 : 0
                    Text {
                        anchors.centerIn: parent
                        text: "History (" + notifModel.history.length + ")"
                        color: root.showHistory ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                        font.pixelSize: Theme.Tokens.typographyLabelMedium
                    }
                    TapHandler { onTapped: root.showHistory = true }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
            }

            // ── Notification list ──
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Empty state
                Text {
                    anchors.centerIn: parent
                    text: root.showHistory ? "No history" : "No notifications"
                    color: Theme.Tokens.textMuted
                    font.pixelSize: Theme.Tokens.typographyBodyMedium
                    visible: (root.showHistory ? notifModel.history.length : notifModel.notifications.length) === 0
                }

                Flickable {
                    anchors.fill: parent
                    contentHeight: listContent.height + Theme.Tokens.spacingLg
                    interactive: contentHeight > height

                    ColumnLayout {
                        id: listContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: Theme.Tokens.spacingSm

                        Repeater {
                            model: root.showHistory ? notifModel.history : notifModel.notifications
                            delegate: Components.NotificationItem {
                                required property var modelData
                                notification: modelData
                                Layout.fillWidth: true
                                onDismissed: notifModel.dismissNotification(modelData.id)
                                onActionInvoked: function(notification, actionId) {
                                    // Notify daemon if connected
                                    if (root.noxd && root.noxd.connected) {
                                        root.noxd.runAction({ notification_action: { id: notification.id, action: actionId } });
                                    }
                                    if (actionId === "dismiss" || actionId === "dismiss") {
                                        notifModel.dismissNotification(notification.id);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Public API ──
    function open() {
        panelOpen = true;
        showHistory = false;
        openProgress = 1;
    }

    SequentialAnimation {
        id: closeAnim
        NumberAnimation {
            target: root; property: "openProgress"
            from: 1; to: 0; duration: 150; easing.type: Easing.InCubic
        }
        onFinished: root.panelOpen = false
    }

    function close() {
        closeAnim.start();
    }

    function toggle() {
        if (panelOpen) close(); else open();
    }
}
