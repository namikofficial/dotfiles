import QtQuick
import "../theme" as Theme

Rectangle {
    id: root
    property string text: "Tooltip"
    property Item target
    visible: target && target.hovered
    implicitWidth: label.implicitWidth + Theme.Tokens.spacingMd
    implicitHeight: label.implicitHeight + Theme.Tokens.spacingSm
    radius: Theme.Tokens.radiusSm
    color: Theme.Tokens.surfaceInverseSurface
    border.color: Theme.Tokens.outlineStrong
    border.width: 1
    z: 200
    x: target ? target.x : 0
    y: target ? target.y + target.height + Theme.Tokens.spacingXs : 0
    Text { id: label; anchors.centerIn: parent; text: root.text; color: Theme.Tokens.surfaceInverseOnSurface; font.pixelSize: Theme.Tokens.typographyBodySmall }
}
