import QtQml
import "ModelUtils.js" as Utils

ProviderModel {
    providerName: "audio"
    property int outputVolume: 0
    property int inputVolume: 0
    property bool outputMuted: false
    property bool inputMuted: false
    property var outputs: []
    property var inputs: []
    property var streams: []
    property int maxVolume: 100

    function applySnapshot(snapshot) {
        if (!Utils.applyBase(this, snapshot, providerName)) return false;
        var next = snapshot.data;
        outputVolume = Utils.numberOr(next.output_volume, 0);
        inputVolume = Utils.numberOr(next.input_volume, 0);
        outputMuted = next.output_muted === true;
        inputMuted = next.input_muted === true;
        outputs = Array.isArray(next.outputs) ? next.outputs : [];
        inputs = Array.isArray(next.inputs) ? next.inputs : [];
        streams = Array.isArray(next.streams) ? next.streams : [];
        maxVolume = Utils.numberOr(next.max_volume, 100);
        return true;
    }
}
