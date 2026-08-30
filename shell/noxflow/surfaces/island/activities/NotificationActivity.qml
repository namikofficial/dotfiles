import QtQuick
import QtQuick.Layouts
import "../../../theme" as Theme

// Notification banner for the island.
Item {
    id: root

    property string summary: ""
    property string body: ""

    RowLayout {
        anchors.fill: parent
        spacing: Theme.Tokens.spacingMd

        Text {
            text: "◈"
            color: Theme.Tokens.tonalPrimary
            font.pixelSize: Theme.Tokens.iconMd
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.Tokens.spacingXs

            Text {
                text: root.summary || "Notification"
                color: Theme.Tokens.textPrimary
                font.pixelSize: Theme.Tokens.typographyBodyMedium
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                text: root.body || ""
                color: Theme.Tokens.textSecondary
                font.pixelSize: Theme.Tokens.typographyLabelSmall
                elide: Text.ElideRight
                Layout.fillWidth: true
                visible: text !== ""
            }
        }
    }
}
