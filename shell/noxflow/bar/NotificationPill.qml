import QtQuick
import "../theme" as Theme
import "." as Local

// NotificationPill.qml — notification count / DND state in the bar's right zone.



Local.BarStatusPill {
    id: root

    required property int count
    required property bool dnd

    signal activated()
    signal hoverChangedToIsland(bool hovered)

    occupied: true
    minimumWidth: Theme.Tokens.scaled(Theme.Tokens.heightChip)
    tooltipText: dnd
        ? "Do Not Disturb is on"
        : count > 0 ? count + " unread notification" + (count === 1 ? "" : "s")
                    : "No unread notifications"

    onTapped: root.activated()

    property bool hover: false
    onHoverChanged: function(hovered) { root.hover = hovered; root.hoverChangedToIsland(hovered) }

    readonly property string glyph: dnd ? "" : count > 0 ? "" : ""
    readonly property color glyphColor: dnd
        ? Theme.Tokens.stateWarning
        : count > 0 ? Theme.Tokens.tonalPrimary : Theme.Tokens.tonalSecondary

    Text {
        text: root.glyph
        color: root.glyphColor
        font.family: Theme.Tokens.iconFont
        font.pixelSize: Theme.Tokens.iconSm
    }
    Text {
        visible: root.count > 0
        text: String(root.count)
        color: Theme.Tokens.tonalPrimary
        font.family: Theme.Tokens.typographyFontFamily
        font.pixelSize: Theme.Tokens.typographyLabelSmall
        font.bold: true
    }
}