import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../theme" as Theme
import "../../components" as Components

Item {
    id: root

    required property var noxd
    required property var transfer
    // Capture stable device ID at selection time to avoid index-staleness bugs
    // when devices reorder or are removed between user selection and file picker.
    property string selectedDeviceId: ""
    property bool picking: false
    // Shown when a send was attempted but could not proceed.
    property string pickError: ""
    implicitHeight: contentColumn.implicitHeight

    Connections {
        target: root.transfer
        function onDevicesChanged() {
            if (!root.selectedDeviceId) return
            var present = root.transfer.devices.some(function (device) {
                return device.id === root.selectedDeviceId
            })
            if (!present) root.selectedDeviceId = ""
        }
    }

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
        if (picking || !root.selectedDeviceId)
            return
        picking = true
        fileDialog.open()
    }

    // Qt's own file picker. The previous implementation shelled out to
    // `zenity --file-selection`, which is not installed on this workstation,
    // so "Send files…" never opened anything and reported nothing.
    FileDialog {
        id: fileDialog
        title: "Choose files to send"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["All files (*)"]
        onAccepted: {
            root.picking = false
            root.pickError = ""
            if (!root.selectedDeviceId) return
            // Verify the captured device ID is still present: the peer may have
            // left while the picker was open, and sending then would target a
            // different device than the one the user selected.
            var deviceStillPresent = root.transfer.devices.some(function (device) {
                return device.id === root.selectedDeviceId
            })
            if (!deviceStillPresent) {
                console.warn("quick-share: selected device", root.selectedDeviceId,
                             "no longer present after picker; discarding")
                root.selectedDeviceId = ""
                root.pickError = "The selected device is no longer available"
                return
            }
            var paths = [];
            for (var i = 0; i < selectedFiles.length; i++) {
                var path = String(selectedFiles[i]).replace("file://", "")
                if (path.trim() !== "") paths.push(path)
            }
            if (paths.length === 0) return
            root.transfer.send(root.selectedDeviceId, paths)
        }
        onRejected: {
            root.picking = false
            root.pickError = ""
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

                        Components.Slider {
                            Layout.fillWidth: true
                            readOnly: true
                            accessibleName: "Transfer to " + modelData.peer_alias
                            value: root.progress(modelData)
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
                    Layout.fillWidth: true
                    implicitHeight: 50
                    radius: Theme.Tokens.radiusMd
                    // Use stable device ID comparison instead of array index
                    color: modelData.id === root.selectedDeviceId ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainer
                    border.color: modelData.id === root.selectedDeviceId ? Theme.Tokens.tonalPrimary : "transparent"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.Tokens.spacingSm

                        Text {
                            text: "\uF109"
                            color: Theme.Tokens.tonalPrimary
                            font.family: Theme.Tokens.iconFont
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
                        onTapped: root.selectedDeviceId = modelData.id
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
                enabled: !!root.selectedDeviceId && !root.picking
                onClicked: root.sendFiles()
            }

            Text {
                visible: root.pickError !== ""
                text: root.pickError
                color: Theme.Tokens.stateDanger
                font.pixelSize: Theme.Tokens.typographyLabelSmall
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
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
