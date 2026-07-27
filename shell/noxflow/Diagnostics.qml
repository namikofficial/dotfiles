import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
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

    visible: true
    width: 820
    height: 620
    color: "#11141C"
    title: "NoxFlow IPC diagnostics"

    function healthLine(name) { return name + ": " + (client.providerHealth[name] || "pending"); }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12
        Label { text: "NoxFlow development diagnostics"; color: "#F2F5FA"; font.pixelSize: 22 }
        Label { text: "Connection: " + (client.connected ? "connected" : client.connecting ? "connecting" : "disconnected"); color: client.connected ? "#8FE3B0" : "#F4B183" }
        Label { text: "Protocol: " + (client.protocolVersion || "not negotiated") + "    Events: " + client.eventCount; color: "#D7DEEA" }
        Label { text: "Last event: " + client.lastEvent; color: "#D7DEEA"; elide: Text.ElideRight; Layout.fillWidth: true }
        Label { text: "Last error: " + (client.lastError || "none"); color: client.lastError ? "#F28B82" : "#9EA8B8"; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Rectangle { Layout.fillWidth: true; height: 1; color: "#303746" }
        Label { text: "Provider health"; color: "#F2F5FA"; font.pixelSize: 17 }
        GridLayout {
            columns: 2; rowSpacing: 5; columnSpacing: 24
            Label { text: root.healthLine("hyprland"); color: "#D7DEEA" }
            Label { text: root.healthLine("audio"); color: "#D7DEEA" }
            Label { text: root.healthLine("brightness"); color: "#D7DEEA" }
            Label { text: root.healthLine("power"); color: "#D7DEEA" }
            Label { text: root.healthLine("network"); color: "#D7DEEA" }
            Label { text: root.healthLine("bluetooth"); color: "#D7DEEA" }
            Label { text: root.healthLine("media"); color: "#D7DEEA" }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: "#303746" }
        Label { text: "Models loaded: Hyprland, Audio, Brightness, Battery/Power, Network, Bluetooth, Media"; color: "#9EA8B8"; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Item { Layout.fillHeight: true }
    }
}
