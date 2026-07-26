import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// NoxFlow's first vertical slice. Quickshell integration owns the layer surface
// and IPC adapter; this component deliberately contains no shell commands.
ApplicationWindow {
    id: root
    visible: true
    width: 900
    height: 48
    color: "#11141C"
    title: "NoxFlow"

    Row {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 18

        Label { text: "1  2  3  4"; color: "#F2F5FA" }
        Label { text: "NoxFlow"; color: "#9EA8B8"; Layout.alignment: Qt.AlignVCenter }
        Item { width: 1; Layout.fillWidth: true }
        Label { text: Qt.formatTime(new Date(), "hh:mm"); color: "#F2F5FA" }
        Label { text: "⌁  ◉  ◒"; color: "#9EA8B8" }
    }
}
