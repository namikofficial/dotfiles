// NotificationCentre — notification drawer. Super+N.
// Groups by app, DND toggle, history, clear all, inline actions.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../../theme" as Theme
import "../../components" as Components
import "NotificationGrouping.js" as Grouping

Item {
    id: root
    property var screen
    required property var noxd; required property var notifModel; required property var morphRegistry
    // The bridge owns the live set on the bus; the model is only the
    // shell-side presentation of it. Dismissals and "clear" must go
    // through the bridge so the sending application is actually told.
    required property var bridge

    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    Behavior on openProgress { NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType } }

    property bool showHistory: false

    readonly property var currentItems: root.showHistory
        ? (notifModel.history || [])
        : (notifModel.notifications || [])
    readonly property var groupedItems: notifModel.privacyRedacted
        ? []
        : Grouping.groupByApp(currentItems)
    readonly property bool isEmpty: notifModel.privacyRedacted || currentItems.length === 0

    readonly property string headerSubtitle: {
        if (notifModel.privacyRedacted) return "Protected while locked or sharing";
        if (root.showHistory) {
            return currentItems.length > 0
                ? currentItems.length + " archived"
                : "";
        }
        if (notifModel.dnd) {
            return currentItems.length > 0
                ? "Do Not Disturb on · " + currentItems.length + " critical"
                : "Do Not Disturb on";
        }
        if (currentItems.length > 0) {
            return currentItems.length + " unread";
        }
        return "";
    }

    readonly property real headerHeight: headerRow.implicitHeight
    readonly property real controlsHeight: controlsRow.visible
        ? controlsRow.implicitHeight + Theme.Tokens.spacingMd : 0
    readonly property real warningHeight: ingressWarning.visible
        ? ingressWarning.implicitHeight + Theme.Tokens.spacingMd : 0
    readonly property real dividerHeight: dividerItem.implicitHeight + Theme.Tokens.spacingMd
    readonly property real bodyPreferredHeight: root.isEmpty
        ? Math.max(Theme.Tokens.scaled(140), emptyState.implicitHeight + Theme.Tokens.scaled(28))
        : Math.max(Theme.Tokens.scaled(104), listCol.implicitHeight + Theme.Tokens.spacingSm)
    readonly property real preferredHeight: Math.ceil(
        Theme.Tokens.spacingLg * 2
        + headerHeight
        + Theme.Tokens.spacingMd
        + controlsHeight
        + warningHeight
        + dividerHeight
        + bodyPreferredHeight
    )

    // Right-side panel
    implicitWidth: Theme.Tokens.scaled(420)
    implicitHeight: preferredHeight
    anchors.fill: parent
    visible: lifecycle.active

    Connections { target: lifecycle; function onOpened() { showHistory = false; } }

    FocusScope { id: focusRoot; focus: lifecycle.interactive && !notifModel.privacyRedacted; anchors.fill: parent; Keys.onEscapePressed: lifecycle.requestClose("escape") }

    // Panel
    Rectangle {
        anchors.fill: parent; radius: Theme.Tokens.radiusXl
        color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh)
        border.color: Theme.Tokens.glass(Theme.Tokens.outlineDefault, Theme.Tokens.glassBorderAlpha)
        border.width: 1
        opacity: root.openProgress
        scale: 0.9 + 0.1 * root.openProgress
        transformOrigin: Item.TopRight

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.Tokens.spacingLg
            spacing: Theme.Tokens.spacingMd

            // Header
            RowLayout {
                id: headerRow
                Layout.fillWidth: true
                spacing: Theme.Tokens.spacingSm

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: notifModel.privacyRedacted ? "Notifications hidden" : (root.showHistory ? "History" : "Notifications")
                        color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.typographyTitleLarge
                        font.family: Theme.Tokens.typographyDisplayFamily
                        font.bold: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: root.headerSubtitle !== ""
                        text: root.headerSubtitle
                        color: notifModel.dnd && !root.showHistory && !notifModel.privacyRedacted
                            ? Theme.Tokens.stateWarning : Theme.Tokens.textMuted
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                Components.TextButton {
                    text: "Clear"
                    accessibleName: root.showHistory ? "Clear notification history" : "Clear notifications"
                    visible: !notifModel.privacyRedacted && ((!root.showHistory && notifModel.notifications.length > 0) || (root.showHistory && notifModel.history.length > 0))
                    onClicked: root.showHistory ? notifModel.clearHistory() : root.bridge.closeAll()
                }
                Components.IconButton {
                    iconText: "\uF00D"
                    accessibleName: "Close"
                    onClicked: lifecycle.requestClose("closeButton")
                }
            }

            // Segmented tabs + quiet DND switch
            RowLayout {
                id: controlsRow
                Layout.fillWidth: true
                spacing: Theme.Tokens.spacingMd
                visible: !notifModel.privacyRedacted

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                    radius: Theme.Tokens.radiusPill
                    color: Theme.Tokens.surfaceSurfaceContainer
                    border.color: Theme.Tokens.outlineSubtle
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.Tokens.scaled(3)
                        spacing: Theme.Tokens.scaled(2)

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.Tokens.radiusPill
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: "Active notifications tab"
                            color: !root.showHistory ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                            border.color: !root.showHistory ? Theme.Tokens.tonalPrimary : (activeFocus ? Theme.Tokens.outlineFocus : "transparent")
                            border.width: !root.showHistory || activeFocus ? 1 : 0
                            Text {
                                anchors.centerIn: parent
                                text: "Active (" + notifModel.notifications.length + ")"
                                color: !root.showHistory ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                                font.family: Theme.Tokens.typographyFontFamily
                                font.pixelSize: Theme.Tokens.typographyLabelMedium
                                font.bold: !root.showHistory
                            }
                            TapHandler { onTapped: { root.showHistory = false; parent.forceActiveFocus(); } }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            Keys.onReturnPressed: root.showHistory = false
                            Keys.onSpacePressed: root.showHistory = false
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.Tokens.radiusPill
                            activeFocusOnTab: true
                            Accessible.role: Accessible.Button
                            Accessible.name: "Notification history tab"
                            color: root.showHistory ? Theme.Tokens.tonalPrimaryContainer : "transparent"
                            border.color: root.showHistory ? Theme.Tokens.tonalPrimary : (activeFocus ? Theme.Tokens.outlineFocus : "transparent")
                            border.width: root.showHistory || activeFocus ? 1 : 0
                            Text {
                                anchors.centerIn: parent
                                text: "History (" + notifModel.history.length + ")"
                                color: root.showHistory ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                                font.family: Theme.Tokens.typographyFontFamily
                                font.pixelSize: Theme.Tokens.typographyLabelMedium
                                font.bold: root.showHistory
                            }
                            TapHandler { onTapped: { root.showHistory = true; parent.forceActiveFocus(); } }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            Keys.onReturnPressed: root.showHistory = true
                            Keys.onSpacePressed: root.showHistory = true
                        }
                    }
                }

                RowLayout {
                    spacing: Theme.Tokens.spacingXs
                    Text {
                        text: "DND"
                        color: notifModel.dnd ? Theme.Tokens.stateWarning : Theme.Tokens.textSecondary
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyLabelMedium
                        font.bold: notifModel.dnd
                    }
                    Components.Toggle {
                        accessibleName: "Do Not Disturb"
                        checked: notifModel.dnd
                        onToggled: notifModel.toggleDnd()
                    }
                }
            }

            Text {
                id: ingressWarning
                Layout.fillWidth: true
                // Quickshell owns the bus outright now that dunst is retired, so
                // there is no "someone else owns this" state left to warn about.
                // The text remains as a live assertion of that invariant.
                visible: !root.showHistory && notifModel.ingressStatus !== "quickshell"
                text: "Notifications are not owned by NoxFlow; the shell cannot track them."
                color: Theme.Tokens.stateWarning
                font.pixelSize: Theme.Tokens.typographyLabelSmall
                wrapMode: Text.Wrap
            }

            Components.Divider {
                id: dividerItem
                Layout.fillWidth: true
            }

            // List area
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    id: emptyState
                    anchors.centerIn: parent
                    width: parent.width - Theme.Tokens.scaled(24)
                    spacing: Theme.Tokens.spacingXs
                    visible: root.isEmpty

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Theme.Tokens.scaled(42)
                        Layout.preferredHeight: Theme.Tokens.scaled(42)
                        Layout.bottomMargin: Theme.Tokens.spacingXs
                        radius: Theme.Tokens.radiusPill
                        color: Theme.Tokens.surfaceSurfaceContainer
                        border.color: Theme.Tokens.outlineSubtle
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: notifModel.privacyRedacted ? "\uF023"
                                : (root.showHistory ? "\uF1DA" : (notifModel.dnd ? "\uF1F6" : "\uF0F3"))
                            color: notifModel.dnd && !root.showHistory && !notifModel.privacyRedacted
                                ? Theme.Tokens.stateWarning : Theme.Tokens.tonalSecondary
                            font.family: Theme.Tokens.iconFont
                            font.pixelSize: Theme.Tokens.scaled(16)
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: notifModel.privacyRedacted ? "Details hidden"
                            : (root.showHistory ? "No history yet"
                            : (notifModel.dnd ? "Do Not Disturb is on" : "You’re all caught up"))
                        color: Theme.Tokens.textPrimary
                        font.family: Theme.Tokens.typographyDisplayFamily
                        font.pixelSize: Theme.Tokens.typographyTitleMedium
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        Layout.fillWidth: true
                        text: notifModel.privacyRedacted ? "Notification content is protected while the screen is locked."
                            : (root.showHistory ? "Dismissed notifications will appear here."
                            : (notifModel.dnd ? "Incoming alerts are silenced and saved to History." : "New notifications will appear here."))
                        color: Theme.Tokens.textMuted
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyBodySmall
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Flickable {
                    id: listFlickable
                    anchors.fill: parent
                    clip: true
                    visible: !root.isEmpty
                    contentWidth: width
                    contentHeight: listCol.implicitHeight + Theme.Tokens.spacingXs
                    interactive: contentHeight > height
                    ScrollBar.vertical: ScrollBar {
                        id: notifScrollBar
                        policy: ScrollBar.AsNeeded
                    }

                    Column {
                        id: listCol
                        width: listFlickable.width - (notifScrollBar.visible ? Theme.Tokens.scaled(10) : 0)
                        spacing: Theme.Tokens.spacingMd

                        Repeater {
                            model: root.groupedItems
                            delegate: Column {
                                id: groupCol
                                required property var modelData
                                readonly property var groupData: modelData
                                width: listCol.width
                                spacing: Theme.Tokens.spacingXs

                                RowLayout {
                                    width: groupCol.width
                                    visible: groupData.count > 1
                                    spacing: Theme.Tokens.spacingXs

                                    Text {
                                        text: String(groupData.appName || "System").toUpperCase()
                                        color: Theme.Tokens.textMuted
                                        font.family: Theme.Tokens.typographyFontFamily
                                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                                        font.bold: true
                                        font.letterSpacing: 0.8
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: countBadgeText.implicitWidth + Theme.Tokens.scaled(12)
                                        Layout.preferredHeight: Theme.Tokens.scaled(18)
                                        radius: Theme.Tokens.radiusPill
                                        color: Theme.Tokens.surfaceSurfaceContainer
                                        border.color: Theme.Tokens.outlineSubtle
                                        border.width: 1
                                        Text {
                                            id: countBadgeText
                                            anchors.centerIn: parent
                                            text: String(groupData.count)
                                            color: Theme.Tokens.textSecondary
                                            font.family: Theme.Tokens.typographyFontFamily
                                            font.pixelSize: Theme.Tokens.typographyLabelSmall
                                            font.bold: true
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        visible: !root.showHistory
                                        text: "Dismiss all"
                                        color: Theme.Tokens.tonalPrimary
                                        font.family: Theme.Tokens.typographyFontFamily
                                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                                        font.bold: true
                                        TapHandler {
                                            onTapped: {
                                                var items = groupData.items || [];
                                                for (var i = 0; i < items.length; i++) {
                                                    root.bridge.dismiss(items[i].id);
                                                }
                                            }
                                        }
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    }
                                }

                                Repeater {
                                    model: groupData.items
                                    delegate: Components.NotificationItem {
                                        required property var modelData
                                        notification: modelData
                                        width: groupCol.width
                                        privacyRedacted: notifModel.privacyRedacted
                                        isHistory: root.showHistory
                                        onDismissed: root.showHistory
                                            ? notifModel.removeFromHistory(modelData.id)
                                            : root.bridge.dismiss(modelData.id)
                                        onActionInvoked: function(notif, actionId) {
                                            if (actionId === "dismiss") {
                                                root.bridge.dismiss(notif.id);
                                                return;
                                            }
                                            // A real action goes to the sending
                                            // application, not to the shell's store.
                                            root.bridge.invoke(notif.id, actionId);
                                        }
                                    }
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
