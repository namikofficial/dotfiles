import QtQuick
import QtQuick.Layouts
import "../../theme" as Theme
import "." as Local

// ConnectivityBody.qml — island dashboard for network and Bluetooth.



ColumnLayout {
    id: root

    property var network: null
    property var bluetooth: null

    Layout.fillWidth: true
    spacing: Theme.Tokens.scaled(Theme.Tokens.spacingXs)

    readonly property bool online: network && network.connectivity === "full"

    function firstAddress(list) {
        if (!list || list.length === 0) return "";
        var first = list[0];
        if (first === null || first === undefined) return "";
        if (typeof first === "object")
            return first.address !== undefined ? String(first.address) : String(first);
        return String(first);
    }

    Local.DashboardSection {
        Layout.fillWidth: true
        headline: root.network
            ? (root.network.connectedSsid
                || (root.network.ethernet && root.network.ethernet.length ? "Ethernet" : "Offline"))
            : "Network unavailable"
        headlineColor: root.online ? Theme.Tokens.textPrimary : Theme.Tokens.stateWarning
        details: {
            if (!root.network) return [{ text: "No network snapshot", color: Theme.Tokens.textMuted }];
            return [
                { text: "Signal  " + (root.network.signalStrength !== null && root.network.signalStrength !== undefined
                        ? Math.round(root.network.signalStrength) + "%" : "unavailable")
                    + "  ·  Internet  " + root.network.connectivity },
                { text: "IPv4  " + (root.firstAddress(root.network.ipv4) || "unavailable") },
                { text: "VPN  " + (root.network.vpn && root.network.vpn.length ? "connected" : "not connected") },
                { text: "Bluetooth  " + (root.bluetooth && root.bluetooth.connectedDevices && root.bluetooth.connectedDevices.length
                        ? root.bluetooth.connectedDevices.map(function (device) {
                              return (device.name || "Device")
                                  + (device.battery !== undefined && device.battery !== null
                                      ? " " + Math.round(device.battery) + "%" : "");
                          }).join("  ·  ")
                        : "no connected devices") }
            ];
        }
        footnote: "Throughput, gateway and ping appear when the network snapshot provides them."
    }
}