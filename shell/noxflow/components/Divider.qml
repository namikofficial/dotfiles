import QtQuick
import "../theme" as Theme

Rectangle {
    id: root
    property bool vertical: false
    property int thickness: 1
    property color lineColor: Theme.Tokens.outlineSubtle
    opacity: Theme.Tokens.opacitySubtle
    implicitWidth: vertical ? thickness : parent ? parent.width : 1
    implicitHeight: vertical ? parent ? parent.height : 1 : thickness
    width: vertical ? thickness : implicitWidth
    height: vertical ? implicitHeight : thickness
    color: root.lineColor
}
