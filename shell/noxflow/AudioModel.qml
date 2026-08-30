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
    property var defaultOutput: null
    property var defaultInput: null
    property int maxVolume: 100
    readonly property int outputVolumePercent: maxVolume > 0 ? Math.round(outputVolume / maxVolume * 100) : 0
    readonly property int inputVolumePercent: maxVolume > 0 ? Math.round(inputVolume / maxVolume * 100) : 0
    readonly property string outputName: data && data.default_output && data.default_output.description ? String(data.default_output.description) : defaultOutput && defaultOutput.description ? String(defaultOutput.description) : activeDeviceName(outputs, "Output")
    readonly property string inputName: data && data.default_input && data.default_input.description ? String(data.default_input.description) : defaultInput && defaultInput.description ? String(defaultInput.description) : activeDeviceName(inputs, "Input")

    function activeDeviceName(list, fallback) {
        if (!list || list.length === 0) return fallback === "Output" ? "No output device" : "No input device";
        var active = list.filter(function(d) { return d.active === true; });
        var item = active.length > 0 ? active[0] : list[0];
        return item.description || item.name || fallback;
    }

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
        defaultOutput = next.default_output && typeof next.default_output === "object" ? next.default_output : null;
        defaultInput = next.default_input && typeof next.default_input === "object" ? next.default_input : null;
        maxVolume = Utils.numberOr(next.max_volume, 100);
        return true;
    }
}
