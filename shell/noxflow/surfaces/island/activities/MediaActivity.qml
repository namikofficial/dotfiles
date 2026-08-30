import QtQuick
import QtQuick.Layouts
import "../../../theme" as Theme
import "../../../components" as Components

// Now-playing media tile for the island.
Item {
    id: root

    required property bool expanded
    required property bool mediaAvailable
    property string title: ""
    property string artist: ""
    property string artwork: ""
    property string status: ""

    signal playPause()
    signal previous()
    signal nextClicked()

    implicitHeight: expanded && mediaAvailable ? Theme.Tokens.scaled(180) : Theme.Tokens.scaled(76)

    RowLayout {
        anchors.fill: parent
        spacing: Theme.Tokens.spacingMd

        // Album art
        Rectangle {
            width: Theme.Tokens.scaled(56)
            height: Theme.Tokens.scaled(56)
            radius: Theme.Tokens.radiusMd
            color: Theme.Tokens.surfaceSurfaceVariant
            visible: artwork === ""

            Text {
                anchors.centerIn: parent
                text: "♫"
                color: Theme.Tokens.tonalPrimary
                font.pixelSize: Theme.Tokens.iconLg
            }

            Image {
                anchors.fill: parent
                source: artwork
                fillMode: Image.PreserveAspectCrop
                visible: artwork !== ""
                asynchronous: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.Tokens.spacingXs

            Text {
                text: title || "No track"
                color: Theme.Tokens.textPrimary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyBodyMedium
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                text: artist || ""
                color: Theme.Tokens.textSecondary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyLabelSmall
                elide: Text.ElideRight
                Layout.fillWidth: true
                visible: text !== ""
            }
        }

        // Media controls
        RowLayout {
            spacing: Theme.Tokens.spacingXs
            Components.IconButton {
                iconText: "◀"
                accessibleName: "Previous track"
                onClicked: root.previous()
            }
            Components.IconButton {
                iconText: status === "playing" ? "⏸" : "▶"
                accessibleName: "Play/Pause"
                onClicked: root.playPause()
            }
            Components.IconButton {
                iconText: "▶"
                accessibleName: "Next track"
                onClicked: root.nextClicked()
            }
        }
    }
}
