import QtQuick
import "../theme" as Theme

Rectangle {
    id: root
    property Item targetItem: parent
    anchors.fill: targetItem
    anchors.margins: -2
    radius: Theme.Tokens.radiusSm + 2
    color: "transparent"
    border.color: Theme.Tokens.outlineFocus
    border.width: 2
    visible: targetItem && targetItem.activeFocus
    z: 100
}
