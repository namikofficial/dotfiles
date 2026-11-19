import QtQuick
import Quickshell.Wayland
import "../../theme" as Theme

Item {
    id: root

    required property var client
    property bool selected: false
    property bool overviewOpen: false
    property bool live: false

    signal activated(var client)

    readonly property string address: client && client.address ? String(client.address) : ""
    readonly property string appName: client && client.wayland && client.wayland.appId
        ? String(client.wayland.appId).split(".").pop().replace(/[-_]+/g, " ")
        : "Window"
    readonly property string title: client && client.title ? String(client.title).trim() : ""

    implicitWidth: Theme.Tokens.scaled(300)
    implicitHeight: Theme.Tokens.scaled(190)
    Accessible.role: Accessible.Button
    Accessible.name: (title || appName) + ", " + appName

    Rectangle {
        anchors.fill: parent
        radius: Theme.Tokens.radiusMd
        color: Theme.Tokens.surfaceSurface2
        border.color: Theme.Tokens.outlineSubtle
        border.width: 1
        clip: true

        ScreencopyView {
            id: preview
            anchors.fill: parent
            anchors.bottomMargin: caption.height
            captureSource: root.client ? root.client.wayland : null
            live: root.live
            constraintSize: Qt.size(960, 540)
            Connections {
                target: root
                function onOverviewOpenChanged() {
                    if (root.overviewOpen && !root.live) captureTimer.restart();
                }
                function onClientChanged() {
                    if (root.overviewOpen && !root.live) captureTimer.restart();
                }
            }
        }

        Rectangle {
            anchors.fill: preview
            visible: !preview.hasContent
            color: Theme.Tokens.surfaceSurfaceContainerHigh
            Text {
                anchors.centerIn: parent
                text: root.appName
                color: Theme.Tokens.textMuted
                font.family: Theme.Tokens.typographyDisplayFamily
                font.pixelSize: Theme.Tokens.typographyTitleMedium
            }
        }

        Rectangle {
            id: caption
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Theme.Tokens.scaled(44)
            color: root.selected ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainerHigh
            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.Tokens.scaled(12)
                anchors.rightMargin: Theme.Tokens.scaled(12)
                spacing: Theme.Tokens.scaled(8)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width * 0.38)
                    text: root.appName
                    color: Theme.Tokens.tonalSecondary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - x - Theme.Tokens.scaled(8))
                    text: root.title || "Untitled window"
                    color: Theme.Tokens.textPrimary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyLabelMedium
                    elide: Text.ElideRight
                }
            }
        }
    }

    // Draw the focus ring above both the preview and its caption. A border on
    // the backing rectangle is otherwise painted over by those children.
    Rectangle {
        anchors.fill: parent
        radius: Theme.Tokens.radiusMd
        color: "transparent"
        border.color: Theme.Tokens.outlineFocus
        border.width: Theme.Tokens.scaled(2)
        visible: root.selected
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.activated(root.client) }

    Timer {
        id: captureTimer
        interval: 240
        repeat: false
        onTriggered: {
            if (root.overviewOpen && !root.live && preview.captureSource && !preview.hasContent)
                preview.captureFrame();
        }
    }

    Component.onCompleted: {
        if (root.overviewOpen && !root.live) captureTimer.start();
    }

    Drag.active: dragHandler.active
    Drag.source: root
    Drag.supportedActions: Qt.MoveAction
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2

    DragHandler {
        id: dragHandler
        target: null
    }
}
