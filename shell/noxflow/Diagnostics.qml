import QtQuick
import QtQuick.Layouts
import "theme" as Theme
import "components" as Components

Item {
    id: root
    required property NoxdClient client
    required property HyprlandModel hyprland
    required property AudioModel audio
    required property BrightnessModel brightness
    required property BatteryModel battery
    required property PowerModel power
    required property NetworkModel network
    required property BluetoothModel bluetooth
    required property MediaModel media

    function healthLine(name) { return name + ": " + (client.providerHealth[name] || "pending"); }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.Tokens.spacingMd
        Text { text: "NoxFlow IPC diagnostics"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyHeadlineLarge; font.family: Theme.Tokens.typographyFontFamily }
        Text { text: "Connection: " + (client.connected ? "connected" : client.connecting ? "connecting" : "disconnected"); color: client.connected ? Theme.Tokens.stateSuccess : Theme.Tokens.stateWarning; font.pixelSize: Theme.Tokens.typographyBodyLarge }
        Text { text: "Protocol: " + (client.protocolVersion || "not negotiated") + "    Events: " + client.eventCount; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodyMedium }
        Text { text: "Last event: " + client.lastEvent; color: Theme.Tokens.textSecondary; elide: Text.ElideRight; Layout.fillWidth: true }
        Text { text: "Last error: " + (client.lastError || "none"); color: client.lastError ? Theme.Tokens.stateDanger : Theme.Tokens.textMuted; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Components.Divider { Layout.fillWidth: true }
        Text { text: "Provider health"; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyTitleLarge; font.family: Theme.Tokens.typographyFontFamily }
        GridLayout {
            columns: 2; rowSpacing: Theme.Tokens.spacingSm; columnSpacing: Theme.Tokens.spacingXl
            Repeater { model: ["hyprland", "audio", "brightness", "power", "network", "bluetooth", "media"]; delegate: Text { required property string modelData; text: root.healthLine(modelData); color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodyMedium } }
        }
        Components.Divider { Layout.fillWidth: true }
        Text { text: "Models loaded: Hyprland, Audio, Brightness, Battery/Power, Network, Bluetooth, Media"; color: Theme.Tokens.textMuted; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Item { Layout.fillHeight: true }
    }
}
