// NotificationCentre — right-side notification drawer. Super+N.
// Groups by app, DND toggle, history, clear all, inline actions.

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme" as Theme
import "../../components" as Components

Item {
    id: root
    property var screen
    required property var noxd; required property var notifModel; required property var morphRegistry

    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    Behavior on openProgress { NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType } }

    property bool showHistory: false

    // Right-side panel
    implicitWidth: Theme.Tokens.scaled(380)
    anchors.fill: parent
    visible: lifecycle.active

    Connections { target: lifecycle; function onOpened() { showHistory = false; } }

    FocusScope { id: focusRoot; focus: lifecycle.interactive; anchors.fill: parent; Keys.onEscapePressed: lifecycle.requestClose("escape") }

    // Panel
    Rectangle {
        anchors.fill: parent; radius: Theme.Tokens.radiusXl
        color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh); border.color: Theme.Tokens.glass(Theme.Tokens.outlineDefault, Theme.Tokens.glassBorderAlpha); border.width: 1
        opacity: root.openProgress; scale: 0.9 + 0.1 * root.openProgress; transformOrigin: Item.TopRight

        ColumnLayout {
            anchors.fill: parent; anchors.margins: Theme.Tokens.spacingLg; spacing: Theme.Tokens.spacingMd

            // Header
            RowLayout { Layout.fillWidth: true
                Text { text: root.showHistory ? "History" : "Notifications"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyTitleLarge; font.bold: true; Layout.fillWidth: true }
                Text { text: "Clear"; color: Theme.Tokens.stateInfo; font.pixelSize: Theme.Tokens.typographyLabelMedium
                    visible: (!root.showHistory && notifModel.notifications.length > 0) || (root.showHistory && notifModel.history.length > 0)
                    TapHandler { onTapped: root.showHistory ? notifModel.clearHistory() : notifModel.clearAll() }
                    HoverHandler { cursorShape: Qt.PointingHandCursor } }
                Components.IconButton { iconText: "\uF00D"; accessibleName: "Close"; onClicked: lifecycle.requestClose("closeButton") }
            }

            // DND (only in active tab)
            RowLayout { Layout.fillWidth: true; spacing: Theme.Tokens.spacingMd; visible: !root.showHistory
                Text { text: "Do Not Disturb"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium; Layout.fillWidth: true }
                Components.Toggle { checked: notifModel.dnd; onToggled: notifModel.toggleDnd() }
            }

            Components.Divider { Layout.fillWidth: true }

            // Tab picker
            RowLayout { Layout.fillWidth: true; spacing: Theme.Tokens.spacingXs
                Rectangle { Layout.fillWidth: true; height: Theme.Tokens.scaled(Theme.Tokens.heightChip); radius: Theme.Tokens.radiusPill
                    color: !root.showHistory ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                    border.color: !root.showHistory ? Theme.Tokens.tonalPrimary : "transparent"; border.width: !root.showHistory ? 1 : 0
                    Text { anchors.centerIn: parent; text: "Active (" + notifModel.notifications.length + ")"
                        color: !root.showHistory ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelMedium }
                    TapHandler { onTapped: root.showHistory = false } HoverHandler { cursorShape: Qt.PointingHandCursor } }
                Rectangle { Layout.fillWidth: true; height: Theme.Tokens.scaled(Theme.Tokens.heightChip); radius: Theme.Tokens.radiusPill
                    color: root.showHistory ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                    border.color: root.showHistory ? Theme.Tokens.tonalPrimary : "transparent"; border.width: root.showHistory ? 1 : 0
                    Text { anchors.centerIn: parent; text: "History (" + notifModel.history.length + ")"
                        color: root.showHistory ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelMedium }
                    TapHandler { onTapped: root.showHistory = true } HoverHandler { cursorShape: Qt.PointingHandCursor } }
            }

            // List area
            Item { Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                Text { anchors.centerIn: parent; text: root.showHistory ? "No history" : "No notifications"
                    color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyBodyMedium
                    visible: (root.showHistory ? notifModel.history.length : notifModel.notifications.length) === 0 }

                Flickable {
                    anchors.fill: parent; clip: true
                    contentHeight: listCol.childrenRect.height + Theme.Tokens.spacingMd
                    interactive: contentHeight > height

                    Column { id: listCol; anchors.left: parent.left; anchors.right: parent.right; spacing: Theme.Tokens.spacingSm
                        Repeater {
                            model: root.showHistory ? notifModel.history : notifModel.notifications
                            delegate: Components.NotificationItem {
                                required property var modelData
                                notification: modelData; width: parent ? parent.width : 0
                                onDismissed: notifModel.dismissNotification(modelData.id)
                                onActionInvoked: function(notif, actionId) {
                                    if (root.noxd && root.noxd.connected) root.noxd.runAction({notification_action:{id:notif.id,action:actionId}});
                                    if (actionId === "dismiss") notifModel.dismissNotification(notif.id);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function toggle() { lifecycle.toggle(); }
    function open() { lifecycle.open(); }
    function close() { lifecycle.requestClose("close"); }
}
