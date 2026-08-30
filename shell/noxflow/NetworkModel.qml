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
        // Provider events are partial updates. Preserve fields that are not
        // present instead of turning a valid full snapshot into empty lists.
        connectivity = Utils.stringOr(next.connectivity, connectivity);
        connectedSsid = Utils.stringOr(next.connected_ssid, connectedSsid);
        if (next.signal_strength !== undefined)
            signalStrength = Utils.nullableNumber(next.signal_strength);
        if (next.active_connection !== undefined)
            activeConnection = next.active_connection;
        if (Array.isArray(next.ethernet)) ethernet = next.ethernet;
        if (Array.isArray(next.available_wifi)) availableWifi = next.available_wifi;
        if (Array.isArray(next.ipv4)) ipv4 = next.ipv4;
        if (Array.isArray(next.ipv6)) ipv6 = next.ipv6;
        if (Array.isArray(next.vpn)) vpn = next.vpn;
        if (next.metered !== undefined) metered = next.metered === true;
        if (next.networking_enabled !== undefined) networkingEnabled = next.networking_enabled === true;
        if (next.wifi_enabled !== undefined) wifiEnabled = Utils.nullableBool(next.wifi_enabled);
        if (next.wifi_hardware_enabled !== undefined) wifiHardwareEnabled = Utils.nullableBool(next.wifi_hardware_enabled);
        return true;
    }
}
