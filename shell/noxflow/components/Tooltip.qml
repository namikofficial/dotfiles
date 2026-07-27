import QtQuick
import Quickshell._Window
import "../theme" as Theme

// Tooltips must be a separate popup surface. A child of Bar.qml is clipped to
// the bar's 56px layer-shell surface, so its lower half can never be visible.
PopupWindow {
    id: root
    property string text: "Tooltip"
    property Item target
    property bool targetHovered: target && target.hovered === true

    visible: target && targetHovered && text !== ""
    parentWindow: target ? target.window : null
    implicitWidth: Theme.Tokens.scaled(220)
    implicitHeight: label.implicitHeight + Theme.Tokens.scaled(Theme.Tokens.spacingLg)
    color: "transparent"
    relativeX: target ? target.mapToItem(null, target.width / 2, 0).x - width / 2 : 0
    relativeY: target ? target.mapToItem(null, 0, target.height).y + Theme.Tokens.scaled(Theme.Tokens.spacingXs) : 0

    Rectangle {
        anchors.fill: parent
        radius: Theme.Tokens.radiusSm
        color: Theme.Tokens.surfaceInverseSurface
        border.color: Theme.Tokens.outlineStrong
        border.width: 1

        Text {
            id: label
            x: Theme.Tokens.scaled(Theme.Tokens.spacingSm)
            y: Theme.Tokens.scaled(Theme.Tokens.spacingSm)
            width: parent.width - 2 * Theme.Tokens.scaled(Theme.Tokens.spacingSm)
            text: root.text
            color: Theme.Tokens.surfaceInverseOnSurface
            font.family: Theme.Tokens.typographyFontFamily
            font.pixelSize: Theme.Tokens.typographyBodySmall
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
