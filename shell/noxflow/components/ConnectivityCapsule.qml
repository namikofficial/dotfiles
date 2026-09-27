import QtQuick
import QtQuick.Layouts
import "../theme" as Theme
FocusScope {
    id: root
    required property var network
    required property var bluetooth
    property bool ho: false
    property bool hovered: ho
    signal openNetwork()
    signal openBluetooth()
    property alias networkActionItem: networkAction
    property alias bluetoothActionItem: bluetoothAction
    readonly property var connectedDevices: bluetooth && bluetooth.connectedDevices ? bluetooth.connectedDevices : []
    readonly property bool vpnActive: network && network.vpn && network.vpn.length > 0
    readonly property string shortSsid: { var value = network ? String(network.connectedSsid || "") : ""; return value.length > 12 ? value.slice(0, 10) + "…" : value; }
    readonly property bool online: network && (network.connectivity === "full" || network.connectivity === "limited")
    implicitWidth: Math.max(Theme.Tokens.scaled(Theme.Tokens.heightChip), values.implicitWidth + Theme.Tokens.scaled(24))
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: root.hovered ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62) }
    RowLayout {
        id: values; anchors.centerIn: parent; spacing: Theme.Tokens.scaled(6)
        FocusScope {
            id: networkAction
            activeFocusOnTab: true
            implicitWidth: networkValues.implicitWidth + Theme.Tokens.scaled(8)
            implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
            Accessible.role: Accessible.Button
            Accessible.name: root.online ? "Connected to " + (root.network.connectedSsid || "network") : "Network offline"
            Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: networkAction.activeFocus ? Theme.Tokens.glass(Theme.Tokens.outlineFocus, 0.20) : "transparent"; border.color: networkAction.activeFocus ? Theme.Tokens.outlineFocus : "transparent"; border.width: networkAction.activeFocus ? 2 : 0 }
            RowLayout {
                id: networkValues
                anchors.centerIn: parent
                spacing: Theme.Tokens.scaled(6)
                Text { text: root.vpnActive ? "\uF023" : root.online ? "\uF1EB" : "\uF071"; color: root.online ? Theme.Tokens.textSecondary : Theme.Tokens.stateWarning; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconXs }
                Text { visible: root.shortSsid !== ""; text: root.shortSsid; color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelMedium }
            }
            TapHandler { onTapped: { networkAction.forceActiveFocus(); root.openNetwork(); } }
            Keys.onReturnPressed: root.openNetwork()
            Keys.onSpacePressed: root.openNetwork()
        }
        Rectangle { width: 1; height: Theme.Tokens.scaled(14); color: Theme.Tokens.outlineSubtle }
        FocusScope {
            id: bluetoothAction
            activeFocusOnTab: true
            implicitWidth: bluetoothValues.implicitWidth + Theme.Tokens.scaled(8)
            implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
            Accessible.role: Accessible.Button
            Accessible.name: root.connectedDevices.length > 0
                ? "Bluetooth connected to " + String(root.connectedDevices[0].name || root.connectedDevices.length + " devices")
                : "Open Bluetooth"
            Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusPill; color: bluetoothAction.activeFocus ? Theme.Tokens.glass(Theme.Tokens.outlineFocus, 0.20) : "transparent"; border.color: bluetoothAction.activeFocus ? Theme.Tokens.outlineFocus : "transparent"; border.width: bluetoothAction.activeFocus ? 2 : 0 }
            RowLayout {
                id: bluetoothValues
                anchors.centerIn: parent
                spacing: Theme.Tokens.scaled(6)
                Text { text: "\uF294"; color: root.connectedDevices.length > 0 ? Theme.Tokens.tonalSecondary : Theme.Tokens.textMuted; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconXs }
                Text { visible: root.connectedDevices.length > 0; text: root.connectedDevices.length === 1 ? String(root.connectedDevices[0].name || "Device") : String(root.connectedDevices.length); color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall; elide: Text.ElideRight; Layout.maximumWidth: Theme.Tokens.scaled(72) }
            }
            TapHandler { onTapped: { bluetoothAction.forceActiveFocus(); root.openBluetooth(); } }
            Keys.onReturnPressed: root.openBluetooth()
            Keys.onSpacePressed: root.openBluetooth()
        }
    }
    HoverHandler { onHoveredChanged: root.ho = hovered }
}
