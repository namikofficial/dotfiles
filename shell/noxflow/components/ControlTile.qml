// Tiled quick-control button for Control Centre.
import QtQuick
import QtQuick.Layouts
import "../theme" as Theme

Rectangle {
    id: root
    property string icon: "•"
    property string label: ""
    property string subtitle: ""
    property bool active: true
    property color statusColor: Theme.Tokens.textSecondary
    property bool showToggle: false
    property bool toggleChecked: false
    signal clicked()
    signal toggleChanged(bool value)

    height: Theme.Tokens.scaled(52)
    radius: Theme.Tokens.radiusMd
    color: Theme.Tokens.surfaceSurface
    border.color: Theme.Tokens.outlineSubtle
    border.width: 1

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.Tokens.spacingMd
        spacing: Theme.Tokens.spacingMd
        Text {
            text: root.icon
            color: root.statusColor
            font.pixelSize: Theme.Tokens.iconMd
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                text: root.label
                color: Theme.Tokens.textPrimary
                font.pixelSize: Theme.Tokens.typographyBodyMedium
                font.family: Theme.Tokens.typographyFontFamily
                elide: Text.ElideRight
            }
            Text {
                visible: root.subtitle !== ""
                text: root.subtitle
                color: Theme.Tokens.textMuted
                font.pixelSize: Theme.Tokens.typographyLabelSmall
                elide: Text.ElideRight
            }
        }
        Toggle {
            id: controlToggle
            visible: root.showToggle
            checked: root.toggleChecked
            onToggled: function(value) { root.toggleChanged(value) }
        }
    }
    TapHandler {
        onTapped: { if (root.active && !root.showToggle) root.clicked() }
    }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
}
