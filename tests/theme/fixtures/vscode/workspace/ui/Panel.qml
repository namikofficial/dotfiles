import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property bool active: false
    property int padding: 12
    signal activated(string reason)

    color: root.active ? "#223344" : "transparent"
    radius: 8

    // Content is laid out in a column; spacing comes from the token table.
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.padding
        Text { text: qsTr("Hello, %1").arg(Qt.application.name); font.pixelSize: 14 }
        MouseArea { onClicked: root.activated("click") }
    }
}
