import QtQml
import "ModelUtils.js" as Utils

ProviderModel {
    providerName: "bluetooth"
    property bool adapterPresent: false
    property bool powered: false
    property bool discovering: false
    property var adapters: []
    property var devices: []

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
}
