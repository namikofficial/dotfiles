import QtQuick
import QtQuick.Layouts
import "../../../theme" as Theme

// Timer countdown display for the island.
Item {
    id: root

    property int totalSeconds: 0
    property int remainingSeconds: 0
    property bool active: false

    function formatTime(seconds) {
        var m = Math.floor(seconds / 60);
        var s = seconds % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    implicitHeight: active ? Theme.Tokens.scaled(120) : 0

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Theme.Tokens.spacingSm
        visible: root.active

        Text {
            text: root.formatTime(root.remainingSeconds)
            color: root.remainingSeconds <= 10 ? Theme.Tokens.stateWarning : Theme.Tokens.textPrimary
            font.pixelSize: Theme.Tokens.typographyHeadlineSmall
            font.bold: true
            font.family: Theme.Tokens.typographyFontFamily
            Layout.alignment: Qt.AlignCenter
        }

        // Progress bar
        Rectangle {
            Layout.fillWidth: true
            height: 4
            radius: 2
            color: Theme.Tokens.outlineSubtle
            Rectangle {
                width: parent.width * (root.totalSeconds > 0 ? root.remainingSeconds / root.totalSeconds : 0)
                height: parent.height
                radius: parent.radius
                color: root.remainingSeconds <= 10 ? Theme.Tokens.stateWarning : Theme.Tokens.tonalPrimary
            }
        }
    }
}
