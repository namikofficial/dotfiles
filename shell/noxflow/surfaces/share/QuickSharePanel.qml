import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme" as Theme
import "../../components" as Components

Item {
    id: root
    property var screen
    required property var noxd
    required property var transfer
    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    Behavior on openProgress { NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType } }
    anchors.fill: parent
    visible: lifecycle.active

    Connections {
        target: lifecycle
        function onOpened() {
            root.transfer.refreshing = true
            root.transfer.discover()
        }
        function onClosed() {
            root.transfer.refreshing = false
        }
    }

    Component.onDestruction: root.transfer.refreshing = false

    FocusScope {
        anchors.fill: parent
        focus: lifecycle.interactive
        Keys.onEscapePressed: lifecycle.requestClose("escape")

        Rectangle {
            anchors.fill: parent
            radius: Theme.Tokens.radiusXl
            color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh)
            border.color: Theme.Tokens.glass(Theme.Tokens.outlineDefault, Theme.Tokens.glassBorderAlpha)
            border.width: 1
            opacity: root.openProgress
            scale: 0.92 + root.openProgress * 0.08

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.Tokens.spacingLg
                spacing: Theme.Tokens.spacingMd

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "Quick Share"
                        color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.typographyTitleLarge
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Components.IconButton {
                        iconText: "\uF021"
                        accessibleName: "Discover devices"
                        onClicked: root.transfer.discover()
                    }

                    Components.IconButton {
                        iconText: "\uF00D"
                        accessibleName: "Close quick share"
                        onClicked: lifecycle.requestClose("closeButton")
                    }
                }

                QuickShareContent {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    noxd: root.noxd
                    transfer: root.transfer
                }
            }
        }
    }
    function toggle() { lifecycle.toggle(); }
    function open() { lifecycle.open(); }
    function close() { lifecycle.requestClose("close"); }
}
