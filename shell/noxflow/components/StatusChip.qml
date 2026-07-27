import QtQuick
import "../theme" as Theme

Rectangle {
    id: root
    property string text: "Status"
    property string status: "info"
    property color statusColor: status === "success" ? Theme.Tokens.stateSuccess : status === "warning" ? Theme.Tokens.stateWarning : status === "danger" ? Theme.Tokens.stateDanger : Theme.Tokens.stateInfo
    implicitWidth: label.implicitWidth + Theme.Tokens.spacingLg
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
    radius: Theme.Tokens.radiusPill
    color: Theme.Tokens.withAlpha(root.statusColor, 0.18)
    border.color: root.statusColor
    border.width: 1
    Text { id: label; anchors.centerIn: parent; text: root.text; color: root.statusColor; font.pixelSize: Theme.Tokens.typographyLabelMedium; font.family: Theme.Tokens.typographyFontFamily }
}
