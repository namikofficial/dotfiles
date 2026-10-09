import QtQuick
import QtQuick.Layouts
import "../../../theme" as Theme
import "../../../components" as Components

// Bluetooth — adapter power and device management.
//
// Extracted from ControlCentre.qml, which was 1531 lines and mixed this tab
// with the host, the other six tabs, the tab bar and the Wi-Fi connect flow.
// The tab reaches the host through `host` instead of a dozen individually
// forwarded properties, so a new host property is reachable from here
// without touching this component.

Flickable {
    id: tabRoot

    // The owning ControlCentre. Every model and action used below lives
    // there; see the file header.
    required property var host
    anchors.fill: parent
    contentWidth: width
    contentHeight: bluetoothContent.height + Theme.Tokens.spacingLg
    visible: host.state.activeTab === 3
    interactive: contentHeight > height
    ColumnLayout {
        id: bluetoothContent
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.Tokens.spacingMd

        RowLayout {
            Layout.fillWidth: true
            Text { text: "Bluetooth"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }
            Item { Layout.fillWidth: true }
            Components.Toggle {
                accessibleName: "Bluetooth"
                enabled: host.bluetooth.adapterPresent
                checked: host.bluetooth.powered
                onToggled: function(value) {
                    if (host.noxd.connected) {
                        host.noxd.runAction({ bluetooth_set_powered: { powered: value } });
                        host.state.markAction("bluetooth", value ? "Turning Bluetooth on…" : "Turning Bluetooth off…");
                    }
                }
            }
        }
        Components.IconButton {
            iconText: host.bluetooth.discovering ? "◉" : "◌"
            accessibleName: "Discover devices"
            enabled: host.bluetooth.powered
            onClicked: { if (host.noxd.connected) host.noxd.runAction({ bluetooth_set_discovering: { discovering: !host.bluetooth.discovering } }) }
        }
        Text {
            visible: host.bluetooth.discovering
            text: "Discovering nearby devices…"
            color: Theme.Tokens.tonalPrimary
            font.pixelSize: Theme.Tokens.typographyBodySmall
        }

        Components.Divider { Layout.fillWidth: true }
        Text { text: "Devices"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }
        Repeater {
            model: host.bluetooth.devices
            delegate: Rectangle {
                required property var modelData
                width: parent ? parent.width : 100
                height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                radius: Theme.Tokens.radiusSm
                color: modelData.connected ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainer
                border.color: modelData.connected ? Theme.Tokens.tonalPrimary : "transparent"
                border.width: modelData.connected ? 1 : 0
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.Tokens.spacingSm
                    Text { text: modelData.icon || "◈"; color: modelData.connected ? Theme.Tokens.tonalPrimary : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.iconSm }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 0
                        Text { text: modelData.name || "Unknown"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodySmall; elide: Text.ElideRight }
                        Text { text: modelData.connected ? "Connected" : modelData.paired ? "Paired" : ""; color: modelData.connected ? Theme.Tokens.stateSuccess : Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                    }
                    Rectangle {
                        height: Theme.Tokens.scaled(Theme.Tokens.heightChip - 8)
                        implicitWidth: Theme.Tokens.scaled(50)
                        radius: Theme.Tokens.radiusPill
                        color: Theme.Tokens.surfaceSurfaceVariant
                        visible: modelData.connected
                        Text {
                            anchors.centerIn: parent
                            text: "Disconnect"
                            color: Theme.Tokens.textSecondary
                            font.pixelSize: Theme.Tokens.typographyLabelSmall
                        }
                        TapHandler { onTapped: { if (host.noxd.connected) { host.noxd.runAction({ bluetooth_disconnect: { device_id: modelData.id || modelData.path || "" } }); host.state.markAction("bluetooth", "Disconnecting…"); } } }
                    }
                }
                TapHandler { onTapped: { if (host.noxd.connected && !modelData.connected && modelData.paired) { host.noxd.runAction({ bluetooth_connect: { device_id: modelData.id || modelData.path || "" } }); host.state.markAction("bluetooth", "Connecting…"); } } }
            }
        }
    }
}
