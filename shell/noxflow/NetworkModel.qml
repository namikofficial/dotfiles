import QtQml
import "ModelUtils.js" as Utils

ProviderModel {
    providerName: "network"
    property string connectivity: "unknown"
    property string connectedSsid: ""
    property var signalStrength: null
    property var activeConnection: null
    property var ethernet: []
    property var availableWifi: []
    property var ipv4: []
    property var ipv6: []
    property var vpn: []
    property bool metered: false
    property bool networkingEnabled: false
    property var wifiEnabled: null
    property var wifiHardwareEnabled: null
    readonly property bool wifiUsable: available && wifiEnabled !== false && wifiHardwareEnabled !== false
    readonly property string displayState: !available ? "Network unavailable" : wifiEnabled === false ? "Wi-Fi off" : connectivity === "full" && connectedSsid !== "" ? "Connected to " + connectedSsid : connectivity === "limited" ? "Limited connection" : "No connection"

    function applySnapshot(snapshot) {
        if (!Utils.applyBase(this, snapshot, providerName)) return false;
        var next = snapshot.data;
        connectivity = Utils.stringOr(next.connectivity, "unknown");
        connectedSsid = Utils.stringOr(next.connected_ssid, "");
        signalStrength = Utils.nullableNumber(next.signal_strength);
        activeConnection = next.active_connection === undefined ? null : next.active_connection;
        ethernet = Array.isArray(next.ethernet) ? next.ethernet : [];
        availableWifi = Array.isArray(next.available_wifi) ? next.available_wifi : [];
        ipv4 = Array.isArray(next.ipv4) ? next.ipv4 : [];
        ipv6 = Array.isArray(next.ipv6) ? next.ipv6 : [];
        vpn = Array.isArray(next.vpn) ? next.vpn : [];
        metered = next.metered === true;
        networkingEnabled = next.networking_enabled === true;
        wifiEnabled = Utils.nullableBool(next.wifi_enabled);
        wifiHardwareEnabled = Utils.nullableBool(next.wifi_hardware_enabled);
        return true;
    }
}
