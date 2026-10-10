import QtQml
import QtQuick
import Quickshell
import Quickshell.Io
import "../../theme" as Theme
// ModelUtils.asArray, not a bare Array.isArray guard: noxd lists reach QML
// as QML sequence objects, which fail Array.isArray() while reporting a
// correct length. See ModelUtils.js and test_model_utils.js.
import "../../ModelUtils.js" as Utils

// ControlCentreState — the control centre's view state.
//
// Extracted from ControlCentre.qml, which was 1531 lines and mixed this state
// machine with the host chrome, seven tabs, the tab bar and the Wi-Fi connect
// flow. It is a plain QtObject: no geometry, no painting, no animation.
//
// It owns the Wi-Fi connect flow (review -> password -> connecting -> saved),
// the Bluetooth pairing hand-off, the slider commit debounce and the DND
// read-out. The plan moves the Wi-Fi flow itself down into NetworkModel,
// which is the only component that issues the connect action.
//
// A child of ControlCentre, not a peer: the host passes the models it already
// holds, so there is exactly one set of live models in the shell.

QtObject {
    id: state

    // The models this state machine acts through.
    property var screen
    property var noxd
    property var network
    property var bluetooth
    property var audio
    property var power
    property var notificationModel: null

    property int activeTab: 0
    property string initialSection: ""
    property string wifiActionState: ""
    property string bluetoothActionState: ""
    property string bluetoothPasskey: ""
    property string expandedSection: ""
    property string audioActionState: ""
    // The Wi-Fi connect flow lives in NetworkModel (it owns the connect action
    // and the connectedSsid transition that resolves it). These aliases keep
    // every existing `state.wifiX` reference working without a second copy of
    // the state machine — there is exactly one, and it is not here.
    readonly property bool wifiConnectDialogVisible: network.wifiConnectDialogVisible
    readonly property string wifiConnectSsid: network.wifiConnectSsid
    readonly property string wifiConnectSecurity: network.wifiConnectSecurity
    readonly property string wifiConnectPassword: network.wifiConnectPassword
    readonly property bool wifiConnectSaved: network.wifiConnectSaved
    readonly property bool wifiPasswordVisible: network.wifiPasswordVisible
    readonly property string wifiFlowStage: network.wifiFlowStage
    property string wifiBackgroundAttemptSsid: network.wifiBackgroundAttemptSsid
    property string wifiBackgroundStatus: network.wifiBackgroundStatus
    readonly property int wifiAttemptSerial: network.wifiAttemptSerial
    readonly property int wifiActiveAttempt: network.wifiActiveAttempt
    readonly property bool wifiScanPending: network.wifiScanPending
    readonly property bool wifiConnectionPending: network.wifiConnectionPending
    readonly property string wifiError: network.wifiError
    readonly property string wifiConnectionState: network.wifiConnectionState
    readonly property string wifiConnectionMessage: network.wifiConnectionMessage

    // Timers are declared as properties rather than bare children: QtObject has
    // no default property, so an unnamed child object cannot be assigned.
    property Timer actionStateTimer: Timer {
        id: actionStateTimer
        interval: 1800
        repeat: false
        onTriggered: { state.wifiActionState = ""; state.bluetoothActionState = ""; state.audioActionState = ""; }
    }
    // Debounced slider commit
    property real pendingBrightness: -1
    property real pendingVolume: -1
    property Timer sliderCommitTimer: Timer {
        id: sliderCommitTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (state.pendingBrightness >= 0 && state.noxd.connected) {
                state.noxd.runAction({ brightness_set: { percentage: Math.round(state.pendingBrightness * 100) } });
                state.pendingBrightness = -1;
            }
            if (state.pendingVolume >= 0 && state.noxd.connected) {
                state.noxd.runAction({ audio_set_volume: { target: "output", volume: Math.round(state.pendingVolume * (audio.maxVolume || 100)) } });
                state.pendingVolume = -1;
            }
        }
    }
    function queueBrightness(v) { state.pendingBrightness = v; sliderCommitTimer.restart(); }
    function queueVolume(v) { state.pendingVolume = v; sliderCommitTimer.restart(); }
    function markAction(kind, message) {
        if (kind === "wifi") state.wifiActionState = message;
        else if (kind === "bluetooth") state.bluetoothActionState = message;
        else state.audioActionState = message;
        actionStateTimer.restart();
    }

    function pairBluetooth(deviceId) {
        if (!state.noxd.connected || !deviceId) return;
        state.bluetoothActionState = "Pairing…";
        state.noxd.runAction({ bluetooth_pair: { device_id: String(deviceId) } });
    }

    function respondBluetoothPairing(accepted) {
        var request = bluetooth.pairingRequest;
        if (!request || !request.requestId || !state.noxd.connected) return;
        state.noxd.runAction({ bluetooth_pairing_response: {
            request_id: request.requestId,
            accepted: accepted,
            passkey: state.bluetoothPasskey !== "" ? state.bluetoothPasskey : null
        }});
        if (!accepted) bluetooth.clearPairingRequest();
        state.bluetoothPasskey = "";
    }

    function cancelBluetoothPairing() {
        var request = bluetooth.pairingRequest;
        if (request && request.requestId && state.noxd.connected)
            state.noxd.runAction({ bluetooth_cancel_pairing: { request_id: request.requestId } });
        bluetooth.clearPairingRequest();
    }





    // ── Wi-Fi connect flow: delegates to NetworkModel ──
    function openWifiConnect(networkInfo) { network.openWifiConnect(networkInfo); }
    function useAnotherWifiPassword() { network.useAnotherWifiPassword(); }
    function submitWifiConnect(useSavedProfile) { network.submitWifiConnect(useSavedProfile); }
    function cancelWifiConnect() { network.cancelWifiConnect(); }
    function forgetWifi(ssid) { network.forgetWifi(ssid); }
    function dismissWifiBackground() { network.dismissWifiBackground(); }

    function profileName(value) { return value && typeof value === "object" ? String(value.name || "") : String(value || ""); }
    function profileNames() {
        var result = [];
        var source = power ? Utils.asArray(power.availableProfiles) : [];
        for (var i = 0; i < source.length; i++) { var name = profileName(source[i]); if (name !== "") result.push(name); }
        return result.length > 0 ? result : ["power-saver", "balanced", "performance"];
    }
    function wifiList() {
        // Prefer the model's normalised list; fall back to the raw snapshot.
        if (network && network.availableWifi && network.availableWifi.length > 0)
            return network.availableWifi;
        if (network && network.data && network.data.available_wifi !== undefined)
            return Utils.asArray(network.data.available_wifi);
        return [];
    }
    function bluetoothDeviceSubtitle(device) {
        var state = device.connected ? "Connected" : device.paired ? "Saved" : "Nearby";
        var details = [];
        if (device.battery !== undefined && device.battery !== null)
            details.push(String(device.battery) + "%");
        if (device.rssi !== undefined && device.rssi !== null)
            details.push(String(device.rssi) + " dBm");
        return state + (details.length > 0 ? " · " + details.join(" · ") : "");
    }
    function bluetoothCountLabel() {
        var count = bluetooth ? Utils.asArray(bluetooth.devices).length : 0;
        if (count === 0) return "No nearby or saved devices";
        return count + (count === 1 ? " device" : " devices") + " nearby or saved";
    }

    // Do Not Disturb is shell state now (decision 5): Quickshell owns the
    // notification bus and `NotificationModel.dnd` is the single source of
    // truth, shared with the bar pill and the notification centre.
    //
    // The pair this replaces — `dunstctl is-paused` / `set-paused` — could
    // never have worked: `is-paused` is not a real subcommand, so the read
    // always exited non-zero and the tile showed DND as off no matter what
    // the user had set. There is no probe to fail now because there is no
    // external daemon to be out of sync with.
    readonly property bool focusEnabled: !!(notificationModel && notificationModel.dnd)
    readonly property bool dndAvailable: !!notificationModel
}
