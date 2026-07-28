// NotificationCentre — notification history & management panel.
// Super+N to open. Groups by app, supports DND, history, clear all, inline actions.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme" as Theme
import "../../components" as Components

PanelWindow {
    id: root

    required property var noxd
    required property var notifModel
    required property var morphRegistry

    // ── Lifecycle ──
    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    Behavior on openProgress {
        NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType }
    }

    property bool showHistory: false

    anchors.top: true; anchors.left: true; anchors.right: true; anchors.bottom: true
    exclusiveZone: 0; aboveWindows: true; focusable: true; color: "transparent"
    visible: lifecycle.active

    Connections {
        target: lifecycle
        function onOpened() { showHistory = false; }
    }

    // ── Focus + Escape ──
    FocusScope {
        id: focusRoot
        focus: lifecycle.interactive
        anchors.fill: parent
        Keys.onEscapePressed: lifecycle.requestClose("escape")
    }

    // ── Scrim ──
    Rectangle {
        anchors.fill: parent
        color: Theme.Tokens.withAlpha(Theme.Tokens.tonalBackground, 0.5)
        opacity: root.openProgress * 0.8
        visible: root.openProgress > 0
        TapHandler { onTapped: lifecycle.requestClose("clickOutside") }
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
                    onClicked: lifecycle.requestClose("closeButton")
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

            // ── Tab picker ──
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
                                    if (root.noxd && root.noxd.connected)
                                        root.noxd.runAction({ notification_action: { id: notification.id, action: actionId } });
                                    if (actionId === "dismiss")
                                        notifModel.dismissNotification(notification.id);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Public API ──
    function toggle() { lifecycle.toggle(); }
    function open() { lifecycle.open(); }
    function close() { lifecycle.requestClose("close"); }
}
