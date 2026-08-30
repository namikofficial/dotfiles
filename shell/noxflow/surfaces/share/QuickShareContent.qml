import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme" as Theme
import "../../components" as Components

Item {
    id: root

    required property var noxd
    required property var transfer
    property int selectedDeviceIndex: -1
    property bool picking: false
    property string pickBuffer: ""
    implicitHeight: contentColumn.implicitHeight

    function humanSize(bytes) {
        if (!bytes)
            return "0 B"
        var units = ["B", "KB", "MB", "GB"]
        var unit = 0
        while (bytes >= 1024 && unit < units.length - 1) {
            bytes /= 1024
            unit++
        }
        return bytes.toFixed(unit ? 1 : 0) + " " + units[unit]
    }

    function progress(session) {
        if (!session || !session.files || !session.files.length)
            return 0
        var total = 0
        var done = 0
        session.files.forEach(function (file) {
            total += Number(file.size || 0)
            done += Number(file.transferred || 0)
        })
        return total ? done / total : 0
    }

    function sendFiles() {
        if (picking || selectedDeviceIndex < 0)
            return
        picking = true
        pickBuffer = ""
        pickProc.running = true
    }

    property Process pickProc: Process {
        running: false
        command: ["sh", "-c", "XDG_CURRENT_DESKTOP=hyprland GTK_USE_PORTAL=1 zenity --file-selection --multiple --separator='\\n' 2>/dev/null || echo __CANCELLED__"]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (data) {
                root.pickBuffer += String(data || "") + "\n"
            }
        }

        onExited: {
            root.picking = false
            var text = root.pickBuffer.trim()
            root.pickBuffer = ""
            if (!text || text === "__CANCELLED__")
                return
            var paths = text.split("\n").filter(function (path) {
                return path.trim() !== ""
            })
            if (paths.length && root.selectedDeviceIndex >= 0 && root.selectedDeviceIndex < root.transfer.devices.length)
                root.transfer.send(root.transfer.devices[root.selectedDeviceIndex].id, paths)
        }
    }

    Flickable {
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + Theme.Tokens.spacingLg
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: contentColumn
            width: parent.width
            spacing: Theme.Tokens.spacingMd

            Text {
                text: root.transfer.hasSynced ? "LocalSend v2 · ready" : "Connecting to LocalSend…"
                color: root.transfer.hasSynced ? Theme.Tokens.stateSuccess : Theme.Tokens.stateWarning
                font.pixelSize: Theme.Tokens.typographyLabelSmall
                Layout.fillWidth: true
            }

            Text {
                visible: root.transfer.pendingIncoming.length > 0
                text: "Incoming"
                color: Theme.Tokens.textSecondary
                font.pixelSize: Theme.Tokens.typographyTitleMedium
            }

            Repeater {
                model: root.transfer.pendingIncoming

                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 86
                    radius: Theme.Tokens.radiusMd
                    color: Theme.Tokens.tonalPrimaryContainer
                    border.color: Theme.Tokens.tonalPrimary

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.Tokens.spacingMd

                        Text {
                            text: modelData.peer_alias + " wants to send"
                            color: Theme.Tokens.tonalOnPrimaryContainer
                            font.bold: true
                            Layout.fillWidth: true
                        }

                        Text {
                            text: modelData.files.length + " file(s)"
                            color: Theme.Tokens.tonalOnPrimaryContainer
                            font.pixelSize: Theme.Tokens.typographyLabelSmall
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Components.TextButton {
                                text: "Accept"
                                onClicked: root.transfer.accept(modelData.id)
                            }
                            Components.TextButton {
                                text: "Decline"
                                onClicked: root.transfer.decline(modelData.id)
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.transfer.activeTransfers.length > 0
                text: "Transfers"
                color: Theme.Tokens.textSecondary
                font.pixelSize: Theme.Tokens.typographyTitleMedium
            }

            Repeater {
                model: root.transfer.activeTransfers

                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 76
                    radius: Theme.Tokens.radiusMd
                    color: Theme.Tokens.surfaceSurfaceContainer

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.Tokens.spacingMd

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: (modelData.direction === "out" ? "To " : "From ") + modelData.peer_alias
                                color: Theme.Tokens.textPrimary
                                Layout.fillWidth: true
                            }
                            Components.IconButton {
                                iconText: "\uF05E"
                                accessibleName: "Cancel transfer"
                                onClicked: root.transfer.cancel(modelData.id)
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 5
                            radius: 3
                            color: Theme.Tokens.outlineSubtle
                            Rectangle {
                                width: parent.width * root.progress(modelData)
                                height: parent.height
                                radius: 3
                                color: Theme.Tokens.tonalPrimary
                            }
                        }

                        Text {
                            text: Math.round(root.progress(modelData) * 100) + "%"
                            color: Theme.Tokens.textMuted
                            font.pixelSize: Theme.Tokens.typographyLabelSmall
                        }
                    }
                }
            }

            Text {
                text: "Nearby devices"
                color: Theme.Tokens.textSecondary
                font.pixelSize: Theme.Tokens.typographyTitleMedium
            }

            Repeater {
                model: root.transfer.devices

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 50
                    radius: Theme.Tokens.radiusMd
                    color: root.selectedDeviceIndex === index ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainer
                    border.color: root.selectedDeviceIndex === index ? Theme.Tokens.tonalPrimary : "transparent"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.Tokens.spacingSm

                        Text {
                            text: "\uF109"
                            color: Theme.Tokens.tonalPrimary
                            font.family: "Symbols Nerd Font Mono"
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Text {
                                text: modelData.alias
                                color: Theme.Tokens.textPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.ip
                                color: Theme.Tokens.textMuted
                                font.pixelSize: Theme.Tokens.typographyLabelSmall
                            }
                        }

                        Text {
                            text: "Ready"
                            color: Theme.Tokens.stateSuccess
                            font.pixelSize: Theme.Tokens.typographyLabelSmall
                        }
                    }

                    TapHandler {
                        onTapped: root.selectedDeviceIndex = index
                    }
                }
            }

            Text {
                visible: root.transfer.devices.length === 0
                text: "No nearby devices. Press refresh to discover peers."
                color: Theme.Tokens.textMuted
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Components.TextButton {
                Layout.fillWidth: true
                text: root.picking ? "Choosing files…" : "Send files…"
                enabled: root.selectedDeviceIndex >= 0 && !root.picking
                onClicked: root.sendFiles()
            }

            Text {
                visible: root.transfer.sessions.length > 0
                text: "Recent"
                color: Theme.Tokens.textSecondary
                font.pixelSize: Theme.Tokens.typographyTitleMedium
            }

            Repeater {
                model: root.transfer.sessions.filter(function (session) {
                    return session.state === "completed"
                })
                delegate: Text {
                    required property var modelData
                    text: "✓  " + (modelData.direction === "out" ? "Sent to " : "Received from ") + modelData.peer_alias
                    color: Theme.Tokens.textPrimary
                    font.pixelSize: Theme.Tokens.typographyBodySmall
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }
        }
    }
}
