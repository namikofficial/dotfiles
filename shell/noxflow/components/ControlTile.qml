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
    property bool hovered: false
    property bool pressed: false
    signal clicked()
    signal toggleChanged(bool value)

    // Two lines of copy plus vertical padding need more than the old 52px
    // tile; the previous height made subtitles collide with the next row.
    height: Theme.Tokens.scaled(68)
    radius: Theme.Tokens.radiusMd
    color: root.pressed ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHighest, 0.86) : root.hovered ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.76) : Theme.Tokens.glass(Theme.Tokens.surfaceSurface, Theme.Tokens.glassCardAlpha)
    border.color: Theme.Tokens.glass(Theme.Tokens.outlineSubtle, Theme.Tokens.glassBorderAlpha)
    border.width: 1
    scale: root.pressed ? 0.985 : root.hovered ? 1.01 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.Tokens.durationShort; easing.type: Easing.OutCubic } }

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
            spacing: Theme.Tokens.scaled(3)
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
        onPressedChanged: root.pressed = pressed
        onTapped: { if (root.active && !root.showToggle) root.clicked() }
    }
    HoverHandler { cursorShape: Qt.PointingHandCursor; onHoveredChanged: root.hovered = hovered }
}
