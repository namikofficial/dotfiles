import QtQuick
import QtQuick.Layouts
import "../../../theme" as Theme
import "../../../components" as Components

// QuickBluetooth — the Bluetooth section of the Quick tab.
//
// Split out of QuickTab.qml, which had reached 358 lines and so broke the
// plan's "every control-centre file stays under 350 lines" rule. The whole
// section — adapter toggle, scan/discover, the device list, the passkey/pairing
// prompt and the "use as audio output" hand-off — was one 160-line inline block
// with no separation from the tiles above it.
//
// It reaches the host through the same single `host` property the other tabs
// use, so nothing here needs a forwarded model of its own.

ColumnLayout {
    id: root

    // The owning ControlCentre, passed through by QuickTab.
    required property var host
    // Bluetooth details are progressively disclosed from
    // the summary row so the normal sheet stays calm,
    // while the pairing flow remains fully native.
    ColumnLayout {
        visible: host.state.expandedSection === "bluetooth"
        Layout.fillWidth: true
        spacing: Theme.Tokens.spacingSm

        RowLayout {
            Layout.fillWidth: true
            Components.Toggle {
                accessibleName: "Bluetooth adapter"
                enabled: host.bluetooth.adapterPresent && host.noxd.connected
                checked: host.bluetooth.powered
                onToggled: function(value) {
                    host.bluetooth.pairingError = "";
                    host.noxd.runAction({ bluetooth_set_powered: { powered: value } });
                    host.state.markAction("bluetooth", value ? "Turning Bluetooth on…" : "Turning Bluetooth off…");
                }
            }
            Text {
                text: host.bluetooth.powered ? "Nearby and saved devices" : "Turn on to find devices"
                color: Theme.Tokens.textSecondary
                font.pixelSize: Theme.Tokens.typographyLabelSmall
                Layout.fillWidth: true
            }
            Components.TextButton {
                text: host.bluetooth.discovering ? "Stop scan" : "Scan"
                enabled: host.bluetooth.powered && host.noxd.connected
                onClicked: {
                    host.bluetooth.pairingError = "";
                    host.noxd.runAction({ bluetooth_set_discovering: { discovering: !host.bluetooth.discovering } });
                }
            }
        }

        Rectangle {
            visible: host.bluetooth.pairingRequest !== null
            Layout.fillWidth: true
            implicitHeight: pairingPrompt.implicitHeight + Theme.Tokens.spacingLg * 2
            radius: Theme.Tokens.radiusMd
            color: Theme.Tokens.tonalPrimaryContainer
            border.color: Theme.Tokens.tonalPrimary
            border.width: 1
            ColumnLayout {
                id: pairingPrompt
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.Tokens.spacingMd
                spacing: Theme.Tokens.spacingSm
                Text {
                    text: "Pair " + (host.bluetooth.pairingRequest ? host.bluetooth.pairingRequest.deviceName : "device")
                    color: Theme.Tokens.tonalOnPrimaryContainer
                    font.pixelSize: Theme.Tokens.typographyBodyMedium
                    font.bold: true
                    Layout.fillWidth: true
                }
                Text {
                    visible: host.bluetooth.pairingRequest && host.bluetooth.pairingRequest.passkey !== null
                    text: host.bluetooth.pairingRequest && host.bluetooth.pairingRequest.method === "confirmation"
                        ? "Confirm code " + String(host.bluetooth.pairingRequest.passkey)
                        : "Enter the passkey shown by the device"
                    color: Theme.Tokens.tonalOnPrimaryContainer
                    font.pixelSize: Theme.Tokens.typographyBodySmall
                    Layout.fillWidth: true
                }
                Components.TextField {
                    visible: host.bluetooth.pairingRequest && (host.bluetooth.pairingRequest.method === "pin" || host.bluetooth.pairingRequest.method === "passkey")
                    label: "Passkey"
                    placeholderText: "Enter passkey"
                    text: host.state.bluetoothPasskey
                    onTextChanged: host.state.bluetoothPasskey = text
                    Layout.fillWidth: true
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Components.TextButton { text: "Cancel"; onClicked: host.state.cancelBluetoothPairing() }
                    Components.TextButton { text: "Pair"; onClicked: host.state.respondBluetoothPairing(true) }
                }
            }
        }

        Repeater {
            model: host.bluetooth.devices
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: Theme.Tokens.scaled(48)
                radius: Theme.Tokens.radiusSm
                color: modelData.connected ? Theme.Tokens.tonalSecondaryContainer : Theme.Tokens.surfaceSurfaceContainer
                border.color: modelData.connected ? Theme.Tokens.tonalSecondary : Theme.Tokens.outlineSubtle
                border.width: 1
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.Tokens.spacingSm
                    Text {
                        // U+F025 speaker / U+F294 bluetooth, both Nerd Font.
                        text: modelData.device_type === "audio" ? "\uF025" : "\uF294"
                        color: modelData.connected ? Theme.Tokens.tonalSecondary : Theme.Tokens.textMuted
                        font.family: Theme.Tokens.iconFont
                        font.pixelSize: Theme.Tokens.iconSm
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { text: modelData.name || modelData.id || "Bluetooth device"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodySmall; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: host.state.bluetoothDeviceSubtitle(modelData); color: modelData.connected ? Theme.Tokens.stateSuccess : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                    }
                    Components.TextButton {
                        text: modelData.connected ? "Disconnect" : modelData.paired ? "Connect" : "Pair"
                        enabled: host.noxd.connected
                        onClicked: {
                            if (modelData.connected) {
                                host.noxd.runAction({ bluetooth_disconnect: { device_id: modelData.id || "" } });
                                host.state.markAction("bluetooth", "Disconnecting…");
                            } else if (modelData.paired) {
                                host.noxd.runAction({ bluetooth_connect: { device_id: modelData.id || "" } });
                                host.state.markAction("bluetooth", "Connecting…");
                            } else {
                                host.state.pairBluetooth(modelData.id || "");
                            }
                        }
                    }
                }
            }
        }

        Text {
            visible: host.bluetooth.powered && !host.bluetooth.discovering && host.bluetooth.devices.length === 0
            text: "No devices yet. Put your Pixel Buds in pairing mode, then press Scan."
            color: Theme.Tokens.textMuted
            font.pixelSize: Theme.Tokens.typographyBodySmall
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        RowLayout {
            visible: host.bluetooth.pairingState === "completed" && host.bluetooth.devices.some(function(device) { return device.connected && device.device_type === "audio"; })
            Layout.fillWidth: true
            Text { text: "Audio device connected"; color: Theme.Tokens.stateSuccess; font.pixelSize: Theme.Tokens.typographyLabelSmall; Layout.fillWidth: true }
            Components.TextButton {
                text: "Use for host.audio"
                onClicked: {
                    var device = host.bluetooth.devices.filter(function(item) { return item.connected && item.device_type === "audio"; })[0];
                    if (device && host.noxd.connected) host.noxd.runAction({ audio_set_default: { target: "output", selector: device.name || device.id } });
                }
            }
        }

        Text {
            visible: host.bluetooth.pairingError !== ""
            text: host.bluetooth.pairingError
            color: Theme.Tokens.stateDanger
            font.pixelSize: Theme.Tokens.typographyBodySmall
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}
