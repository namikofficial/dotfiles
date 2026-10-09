import QtQuick
import QtQuick.Layouts
import "../../theme" as Theme
import "." as Local

// NotificationPreviewBody.qml — island dashboard for unread notifications.



ColumnLayout {
    id: root

    property var notificationModel: null

    Layout.fillWidth: true
    spacing: Theme.Tokens.scaled(Theme.Tokens.spacingXs)

    readonly property var notes: notificationModel && notificationModel.notifications
        ? notificationModel.notifications : []
    readonly property bool dnd: !!(notificationModel && notificationModel.dnd)

    // At most three previews; the rest is a count, not a wall of text.
    readonly property var recent: {
        var out = [];
        for (var i = Math.max(0, root.notes.length - 3); i < root.notes.length; i++) out.push(root.notes[i]);
        return out;
    }

    Local.DashboardSection {
        Layout.fillWidth: true
        headline: root.dnd
            ? "Do Not Disturb enabled"
            : root.notes.length + " unread"
        headlineColor: root.dnd ? Theme.Tokens.stateWarning : Theme.Tokens.textPrimary
        details: root.notes.length === 0
            ? [{ text: "No unread notifications", color: Theme.Tokens.textMuted }]
            : root.recent.map(function (note) {
                return {
                    text: (note && note.app_name ? note.app_name : "Notification")
                        + "  ·  " + (note && note.summary ? note.summary : (note && note.body ? note.body : ""))
                };
            })
        footnote: root.dnd
            ? "Notifications are held until Do Not Disturb is turned off."
            : ""
        footnoteWrap: true
    }
}