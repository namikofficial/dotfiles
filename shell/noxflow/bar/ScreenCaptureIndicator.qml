import QtQuick
import "../theme" as Theme
import "." as Local

// Detect an active screen capture stream created through the PipeWire portal.
Local.BarStatusPill {
    id: root

    visible: !root.notificationModel || !root.notificationModel.screenCaptureStatusKnown
        || root.notificationModel.screenCaptureActive
    occupied: true
    railItem: true
    minimumWidth: Theme.Tokens.scaled(40)
    horizontalPadding: Theme.Tokens.scaled(10)
    property var notificationModel: null
    tooltipText: !root.notificationModel || !root.notificationModel.screenCaptureStatusKnown
        ? "Screen capture status unavailable — notifications are hidden"
        : "Screen capture or sharing is active — notification details are hidden"

    Text {
        text: "\uF108"
        color: Theme.Tokens.stateDanger
        font.family: Theme.Tokens.iconFont
        font.pixelSize: Theme.Tokens.iconSm
    }
}
