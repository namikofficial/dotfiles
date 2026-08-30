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
    readonly property var connectedDevices: bluetooth && bluetooth.connectedDevices ? bluetooth.connectedDevices : []
    readonly property bool vpnActive: network && network.vpn && network.vpn.length > 0
    readonly property string shortSsid: { var value = network ? String(network.connectedSsid || "") : ""; return value.length > 12 ? value.slice(0, 10) + "…" : value; }
    readonly property bool online: network && (network.connectivity === "full" || network.connectivity === "limited")
    implicitWidth: Math.max(Theme.Tokens.scaled(Theme.Tokens.heightChip), values.implicitWidth + Theme.Tokens.scaled(20))
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: online ? "Connected to " + (network.connectedSsid || "network") : "Network offline"
    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusMd; color: root.hovered ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceHighest, 0.78) : Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.62); border.color: root.activeFocus ? Theme.Tokens.outlineFocus : "transparent"; border.width: root.activeFocus ? 2 : 0 }
    RowLayout {
        id: values; anchors.centerIn: parent; spacing: Theme.Tokens.scaled(6)
        Text { text: root.vpnActive ? "\uF023" : root.online ? "\uF1EB" : "\uF071"; color: root.online ? Theme.Tokens.textSecondary : Theme.Tokens.stateWarning; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconXs }
        Text { visible: root.shortSsid !== ""; text: root.shortSsid; color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelMedium }
        Text { visible: root.connectedDevices.length > 0; text: "\uF294"; color: Theme.Tokens.tonalSecondary; font.family: "Symbols Nerd Font Mono"; font.pixelSize: Theme.Tokens.iconXs }
        Text { visible: root.connectedDevices.length > 0; text: root.connectedDevices.length === 1 ? String(root.connectedDevices[0].name || "Device") : String(root.connectedDevices.length); color: Theme.Tokens.textSecondary; font.family: Theme.Tokens.typographyFontFamily; font.pixelSize: Theme.Tokens.typographyLabelSmall; elide: Text.ElideRight; Layout.maximumWidth: Theme.Tokens.scaled(72) }
    }
    HoverHandler { onHoveredChanged: root.ho = hovered }
    TapHandler { onTapped: root.openNetwork() }
    Keys.onReturnPressed: root.openNetwork()
    Keys.onSpacePressed: root.openNetwork()
}
