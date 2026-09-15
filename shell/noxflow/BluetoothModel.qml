import QtQml
import "ModelUtils.js" as Utils

ProviderModel {
    providerName: "bluetooth"
    property bool adapterPresent: false
    property bool powered: false
    property bool discovering: false
    property var adapters: []
    property var devices: []
    property var pairingRequest: null
    property string pairingState: "idle"
    property string pairingError: ""
    property string lastAction: ""
    readonly property var connectedDevices: devices.filter(function(d) { return d.connected === true; })
    readonly property string displayState: !available || !adapterPresent ? "Bluetooth unavailable" : !powered ? "Bluetooth off" : discovering ? "Discovering" : connectedDevices.length > 0 ? connectedDevices.map(function(d) { return d.name || "Device"; }).join(", ") : "Bluetooth on"

    function applySnapshot(snapshot) {
        if (!Utils.applyBase(this, snapshot, providerName)) return false;
        var next = snapshot.data;
        adapterPresent = next.adapter_present === true;
        powered = next.powered === true;
        discovering = next.discovering === true;
        adapters = Array.isArray(next.adapters) ? next.adapters : [];
        devices = Array.isArray(next.devices) ? next.devices : [];
        return true;
    }

    function applyEvent(event) {
        if (!event || event.provider !== providerName || !event.data) return false;
        if (event.event_type === "pairing_request") {
            pairingRequest = {
                requestId: String(event.data.request_id || ""),
                deviceId: String(event.data.device_id || ""),
                deviceName: String(event.data.device_name || "Bluetooth device"),
                method: String(event.data.method || "confirmation"),
                passkey: event.data.passkey !== undefined ? Number(event.data.passkey) : null
            };
            pairingState = "awaiting-confirmation";
            pairingError = "";
            return true;
        }
        if (event.event_type === "pairing_started") {
            pairingState = "pairing";
            pairingError = "";
            return true;
        }
        if (event.event_type === "pairing_failed") {
            pairingState = "failed";
            pairingError = String(event.data.message || "Bluetooth pairing failed");
            pairingRequest = null;
            return true;
        }
        if (event.event_type === "pairing_complete") {
            pairingState = "completed";
            pairingError = "";
            pairingRequest = null;
            return true;
        }
        return false;
    }

    function clearPairingRequest() {
        pairingRequest = null;
        if (pairingState === "awaiting-confirmation") pairingState = "idle";
    }
}
