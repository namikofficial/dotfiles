import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../theme" as Theme
import "../../components" as Components

PanelWindow {
    id: root

    property var screen
    required property var noxd
    required property var transfer
    required property var syncthing
    property int activeTab: 0

    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress

    Behavior on openProgress {
        NumberAnimation {
            duration: lifecycle.animDuration
            easing.type: lifecycle.easingType
        }
    }

    screen: root.screen
    anchors.left: true
    anchors.top: true
    margins.left: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
    margins.top: Theme.Tokens.scaled(Theme.Tokens.heightToolbar + Theme.Tokens.spacingSm)
    implicitWidth: Theme.Tokens.scaled(430)
    implicitHeight: Math.min(Theme.Tokens.scaled(680), root.screen ? root.screen.height - margins.top - Theme.Tokens.scaled(24) : Theme.Tokens.scaled(680))
    exclusiveZone: 0
    aboveWindows: true
    focusable: true
    color: "transparent"
    visible: lifecycle.active

    Connections {
        target: lifecycle
        function onOpened() {
            root.syncthing.setRefreshing(true)
            root.transfer.refreshing = true
            root.transfer.discover()
        }
        function onClosed() {
            root.syncthing.setRefreshing(false)
            root.transfer.refreshing = false
        }
    }

    Component.onDestruction: {
        root.syncthing.setRefreshing(false)
        root.transfer.refreshing = false
    }

    function stateColor(folder) {
        if (folder.state === "error")
            return Theme.Tokens.stateDanger
        if (folder.state === "syncing")
            return Theme.Tokens.stateInfo
        return Theme.Tokens.stateSuccess
    }

    function eventLabel(event) {
        return String(event.type || event.event || "Syncthing event")
            .replace("ItemFinished", "File finished")
            .replace("ItemStarted", "File started")
            .replace("DeviceConnected", "Device connected")
    }

    FocusScope {
        anchors.fill: parent
        focus: lifecycle.interactive
        Keys.onEscapePressed: lifecycle.requestClose("escape")

        Rectangle {
            anchors.fill: parent
            radius: Theme.Tokens.radiusXl
            color: Theme.Tokens.surfaceSurfaceContainerHigh
            border.color: Theme.Tokens.outlineDefault
            border.width: 1
            opacity: root.openProgress
            scale: 0.9 + root.openProgress * 0.1
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.Tokens.spacingLg
                spacing: Theme.Tokens.spacingMd

                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: "Sync"
                            color: Theme.Tokens.textPrimary
                            font.pixelSize: Theme.Tokens.typographyTitleLarge
                            font.bold: true
                        }
                        Text {
                            text: root.activeTab === 0 ? "Nearby devices, instantly" : "Your files, in rhythm"
                            color: Theme.Tokens.textSecondary
                            font.pixelSize: Theme.Tokens.typographyBodySmall
                        }
                    }
                    Text {
                        text: root.activeTab === 0 ? (root.transfer.hasActiveTransfers ? "Active" : "Ready") : (root.syncthing.syncing ? "Syncing" : root.syncthing.serviceActive ? "Online" : "Offline")
                        color: root.syncthing.hasErrors ? Theme.Tokens.stateDanger : Theme.Tokens.stateSuccess
                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                    }
                    Components.IconButton {
                        iconText: "\uF00D"
                        accessibleName: "Close sync"
                        onClicked: lifecycle.requestClose("closeButton")
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.Tokens.spacingXs
                    Components.TextButton {
                        text: "⇄  Quick Share"
                        onClicked: root.activeTab = 0
                    }
                    Components.TextButton {
                        text: "⟳  Syncthing"
                        onClicked: root.activeTab = 1
                    }
                }

                Components.Divider { Layout.fillWidth: true }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    QuickShareContent {
                        anchors.fill: parent
                        visible: root.activeTab === 0
                        noxd: root.noxd
                        transfer: root.transfer
                    }

                    Flickable {
                        anchors.fill: parent
                        visible: root.activeTab === 1
                        clip: true
                        contentWidth: width
                        contentHeight: syncColumn.implicitHeight + Theme.Tokens.spacingLg
                        interactive: contentHeight > height

                        ColumnLayout {
                            id: syncColumn
                            width: parent.width
                            spacing: Theme.Tokens.spacingMd

                            Text {
                                text: root.syncthing.serviceActive ? "Syncthing is online" : "Syncthing is offline"
                                color: root.syncthing.serviceActive ? Theme.Tokens.stateSuccess : Theme.Tokens.stateWarning
                                font.pixelSize: Theme.Tokens.typographyTitleMedium
                                font.bold: true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Components.TextButton {
                                    text: "Refresh"
                                    onClicked: root.syncthing.refresh()
                                }
                                Components.TextButton {
                                    text: "Restart"
                                    onClicked: root.syncthing.restartService()
                                }
                                Components.TextButton {
                                    text: "Open dashboard"
                                    onClicked: root.syncthing.openUI()
                                }
                            }

                            Text {
                                text: root.syncthing.myId ? "Device " + root.syncthing.myId.substring(0, 18) + "…" : (root.syncthing.lastError || "Waiting for local service")
                                color: Theme.Tokens.textMuted
                                font.pixelSize: Theme.Tokens.typographyLabelSmall
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Text {
                                text: "Folders"
                                color: Theme.Tokens.textSecondary
                                font.pixelSize: Theme.Tokens.typographyTitleMedium
                            }

                            Repeater {
                                model: root.syncthing.folders
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 82
                                    radius: Theme.Tokens.radiusMd
                                    color: Theme.Tokens.surfaceSurfaceContainer
                                    border.color: root.stateColor(modelData)
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingMd
                                        Text {
                                            text: modelData.label || modelData.id
                                            color: Theme.Tokens.textPrimary
                                            font.bold: true
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: (modelData.state || "unknown") + " · " + (modelData.path || "No path")
                                            color: root.stateColor(modelData)
                                            font.pixelSize: Theme.Tokens.typographyLabelSmall
                                            Layout.fillWidth: true
                                            elide: Text.ElideMiddle
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Components.TextButton {
                                                text: modelData.paused ? "Resume" : "Pause"
                                                onClicked: modelData.paused ? root.syncthing.resumeFolder(modelData.id) : root.syncthing.pauseFolder(modelData.id)
                                            }
                                            Components.TextButton {
                                                text: "Rescan"
                                                onClicked: root.syncthing.rescanFolder(modelData.id)
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: root.syncthing.folders.length === 0
                                text: root.syncthing.apiReachable ? "No folders configured" : "Start Syncthing to see folders"
                                color: Theme.Tokens.textMuted
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Text {
                                visible: root.syncthing.devices.length > 0
                                text: "Devices"
                                color: Theme.Tokens.textSecondary
                                font.pixelSize: Theme.Tokens.typographyTitleMedium
                            }

                            Repeater {
                                model: root.syncthing.devices
                                delegate: Text {
                                    required property var modelData
                                    text: (modelData.connected ? "● " : "○ ") + (modelData.name || modelData.id.substring(0, 10))
                                    color: modelData.connected ? Theme.Tokens.stateSuccess : Theme.Tokens.textMuted
                                    Layout.fillWidth: true
                                }
                            }

                            Text {
                                visible: root.syncthing.recentEvents.length > 0
                                text: "Recent activity"
                                color: Theme.Tokens.textSecondary
                                font.pixelSize: Theme.Tokens.typographyTitleMedium
                            }

                            Repeater {
                                model: root.syncthing.recentEvents
                                delegate: Text {
                                    required property var modelData
                                    text: "·  " + root.eventLabel(modelData)
                                    color: Theme.Tokens.textPrimary
                                    font.pixelSize: Theme.Tokens.typographyBodySmall
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function toggle() { lifecycle.toggle() }
    function open() { lifecycle.open() }
    function close() { lifecycle.requestClose("close") }
}
