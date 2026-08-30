import QtQml
import "ModelUtils.js" as Utils

ProviderModel {
    providerName: "brightness"
    property real percentage: 0
    property real minimum: 0
    property real step: 1
    property string backend: ""
    property bool externalBackend: false
    property bool externalSupported: false
    property bool backendAvailable: false

    function applySnapshot(snapshot) {
        if (!Utils.applyBase(this, snapshot, providerName)) return false;
        var next = snapshot.data;
        percentage = Utils.numberOr(next.percentage, 0);
        minimum = Utils.numberOr(next.minimum, 0);
        step = Utils.numberOr(next.step, 1);
        backend = Utils.stringOr(next.backend, "");
        externalBackend = next.external_backend === true;
        externalSupported = next.external_supported === true;
        backendAvailable = next.backend_available === true;
        return true;
    }
}
