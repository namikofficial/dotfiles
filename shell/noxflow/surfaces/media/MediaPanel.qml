import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme" as Theme
import "../../components" as Components

Item {
    id: root
    property var screen
    required property var noxd
    required property var media
    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    Behavior on openProgress { NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType } }

    implicitWidth: Theme.Tokens.scaled(380)
    implicitHeight: Theme.Tokens.scaled(230)
    anchors.fill: parent
    visible: lifecycle.active

    FocusScope {
        id: focusRoot; anchors.fill: parent; focus: lifecycle.interactive
        Keys.onEscapePressed: lifecycle.requestClose("escape")
        Rectangle {
            anchors.fill: parent; radius: Theme.Tokens.radiusXl
            color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh)
            border.color: Theme.Tokens.glass(Theme.Tokens.outlineDefault, Theme.Tokens.glassBorderAlpha); border.width: 1
            opacity: root.openProgress; scale: 0.92 + 0.08 * root.openProgress
            transformOrigin: Item.TopRight
            ColumnLayout {
                anchors.fill: parent; anchors.margins: Theme.Tokens.spacingLg; spacing: Theme.Tokens.spacingMd
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Now playing"; color: Theme.Tokens.textPrimary; font.bold: true; font.pixelSize: Theme.Tokens.typographyTitleLarge; Layout.fillWidth: true }
                    Components.IconButton { iconText: "✕"; accessibleName: "Close media"; onClicked: lifecycle.requestClose("closeButton") }
                }
                Text { text: media.title || "Nothing is playing"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyHeadlineMedium; elide: Text.ElideRight; Layout.fillWidth: true }
                Text { text: media.artists && media.artists.length ? media.artists.join(", ") : (media.album || ""); color: Theme.Tokens.textMuted; elide: Text.ElideRight; Layout.fillWidth: true }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter; spacing: Theme.Tokens.spacingLg
                    Components.IconButton { iconText: "⏮"; accessibleName: "Previous track"; onClicked: root.noxd.runAction({media_previous:{}}) }
                    Components.IconButton { iconText: media.playbackStatus === "playing" ? "⏸" : "▶"; accessibleName: media.playbackStatus === "playing" ? "Pause" : "Play"; onClicked: root.noxd.runAction({media_play_pause:{}}) }
                    Components.IconButton { iconText: "⏭"; accessibleName: "Next track"; onClicked: root.noxd.runAction({media_next:{}}) }
                }
            }
        }
    }
    function toggle() { lifecycle.toggle(); }
    function open() { lifecycle.open(); }
    function close() { lifecycle.requestClose("close"); }
}
