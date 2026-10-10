import QtQuick
import QtQuick.Layouts
import "../../../theme" as Theme
import "../../../components" as Components

// Network — Wi-Fi, wired and connection details.
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
    contentHeight: networkContent.height + Theme.Tokens.spacingLg
    visible: host.state.activeTab === 2
    interactive: contentHeight > height
    ColumnLayout {
        id: networkContent
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.Tokens.spacingMd

        Text { text: "Network"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }
        RowLayout {
            Layout.fillWidth: true
            Text { text: "Wi-Fi"; color: Theme.Tokens.textPrimary }
            Item { Layout.fillWidth: true }
            Components.Toggle {
                accessibleName: "Wi-Fi"
                enabled: host.network.available
                checked: host.network.wifiEnabled === true
                onToggled: function(value) {
                    if (host.noxd.connected) {
                        host.noxd.runAction({ network_wifi_set_enabled: { enabled: value } });
                        host.state.markAction("wifi", value ? "Enabling Wi-Fi…" : "Disabling Wi-Fi…");
                    }
                }
            }
        }
        Text { text: host.network.displayState; color: host.network.connectivity === "full" ? Theme.Tokens.stateSuccess : host.network.connectivity === "limited" ? Theme.Tokens.stateWarning : Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall }
        Rectangle {
            Layout.fillWidth: true
            visible: host.network.connectedSsid !== ""
            Layout.preferredHeight: Theme.Tokens.scaled(58)
            radius: Theme.Tokens.radiusMd
            color: Theme.Tokens.tonalPrimaryContainer
            border.color: Theme.Tokens.tonalPrimary
            border.width: 1
            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.Tokens.spacingMd
                Text { text: "⌁"; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { text: host.network.connectedSsid; color: Theme.Tokens.tonalOnPrimaryContainer; font.pixelSize: Theme.Tokens.typographyBodyMedium; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text { text: "Connected" + (host.network.signalStrength !== null ? " · " + host.network.signalStrength + "% signal" : ""); color: Theme.Tokens.tonalOnPrimaryContainer; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                }
            }
        }

        Components.Divider { Layout.fillWidth: true }
        RowLayout {
            Layout.fillWidth: true
            Text { text: "Available Networks"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge; Layout.fillWidth: true }
            Components.IconButton { iconText: host.state.wifiScanPending ? "…" : "↻"; accessibleName: "Rescan Wi‑Fi networks"; enabled: !host.state.wifiScanPending && host.noxd.connected; onClicked: { host.state.wifiScanPending = true; host.state.wifiError = ""; host.noxd.runAction({ network_refresh: {} }); host.state.markAction("wifi", "Scanning for networks…"); } }
        }
        Text {
            visible: host.state.wifiError !== ""
            text: host.state.wifiError
            color: Theme.Tokens.stateDanger
            font.pixelSize: Theme.Tokens.typographyBodySmall
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Rectangle {
            visible: host.state.wifiBackgroundStatus !== ""
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.Tokens.scaled(44)
            radius: Theme.Tokens.radiusMd
            color: host.state.wifiBackgroundStatus.indexOf("Connected") === 0 ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainer
            border.color: host.state.wifiBackgroundStatus.indexOf("Connected") === 0 ? Theme.Tokens.tonalPrimary : Theme.Tokens.outlineSubtle
            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.Tokens.spacingSm
                Text { text: host.state.wifiBackgroundStatus.indexOf("Connected") === 0 ? "✓" : "◌"; color: host.state.wifiBackgroundStatus.indexOf("Connected") === 0 ? Theme.Tokens.stateSuccess : Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconSm }
                Text { text: host.state.wifiBackgroundStatus; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall; elide: Text.ElideRight; Layout.fillWidth: true }
                Components.TextButton { text: "Dismiss"; onClicked: host.state.dismissWifiBackground() }
            }
        }
        Item {
            visible: host.state.wifiList().length === 0
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.Tokens.scaled(96)
            Text {
                anchors.centerIn: parent
                text: host.state.wifiScanPending ? "Scanning for nearby networks…" : host.network.available ? "No networks found. Press Rescan to search." : "Network provider unavailable"
                color: Theme.Tokens.textMuted
                font.pixelSize: Theme.Tokens.typographyBodyMedium
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                width: parent.width
            }
        }
        Repeater {
            model: host.state.wifiList()
            delegate: Rectangle {
                required property var modelData
                width: networkContent.width
                height: Theme.Tokens.scaled(56)
                radius: Theme.Tokens.radiusMd
                color: modelData.connected ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainer
                border.color: modelData.connected ? Theme.Tokens.tonalPrimary : Theme.Tokens.outlineSubtle
                border.width: 1
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.Tokens.spacingSm
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text { text: modelData.ssid || "Hidden SSID"; elide: Text.ElideRight; Layout.fillWidth: true; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodyMedium; font.bold: modelData.connected === true }
                        Text { text: (modelData.security === "open" ? "Open host.network" : "Password required") + (modelData.saved ? " · Saved" : ""); color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                    }
                    Text { text: modelData.strength !== undefined ? Math.round(modelData.strength) + "%" : "—"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                    Components.TextButton {
                        id: forgetButton
                        visible: modelData.saved === true
                        text: "Forget"
                        onClicked: host.state.forgetWifi(String(modelData.ssid || ""))
                    }
                }
                TapHandler { enabled: !forgetButton.pressed; onTapped: host.state.openWifiConnect(modelData) }
            }
        }

        Components.Divider { Layout.fillWidth: true }
        Text { text: "VPN"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge }
        Repeater {
            model: host.network.vpn
            delegate: Rectangle {
                required property var modelData
                width: parent ? parent.width : 100
                height: Theme.Tokens.scaled(Theme.Tokens.heightChip)
                color: Theme.Tokens.surfaceSurfaceContainer
                radius: Theme.Tokens.radiusSm
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.Tokens.spacingSm
                    Text { text: modelData.name || "VPN"; Layout.fillWidth: true; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyBodySmall }
                    Components.Toggle {
                        accessibleName: (modelData.name || "VPN") + " connection"
                        checked: modelData.active === true
                        onToggled: function(value) { if (host.noxd.connected) host.noxd.runAction({ network_vpn_set_enabled: { uuid: modelData.uuid || "", enabled: value } }) }
                    }
                }
            }
        }
    }
}
