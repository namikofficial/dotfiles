import QtQml
import Quickshell
import "ModelUtils.js" as Utils

ProviderModel {
    providerName: "network"
    // The connect flow issues daemon actions, so the model needs the client.
    // Wired in shell.qml, where the client is declared first.
    property var noxd: null

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

    // ── Wi-Fi connect flow ──
    //
    // review → credentials → connecting → connected/failed.
    //
    // This lived in the control centre's view state, which meant the only
    // component able to act on a network change (this one) could not see the
    // attempt it had to resolve: the host had to watch connectedSsid and poke
    // the flow by hand. The state machine now sits here next to the fields it
    // depends on, and surfaces talk to it directly.
    //
    // Transient "Connecting to…" style messages are emitted as `statusChanged`
    // rather than written into a UI field, so the model stays free of view
    // concerns while still letting the panel show progress.
    property bool wifiConnectDialogVisible: false
    property string wifiConnectSsid: ""
    property string wifiConnectSecurity: ""
    property string wifiConnectPassword: ""
    property bool wifiConnectSaved: false
    property bool wifiPasswordVisible: false
    property string wifiFlowStage: "review"
    // Set when the user closes the dialog while a connect is still in flight:
    // the daemon keeps working, so its outcome is reported as a banner instead.
    property string wifiBackgroundAttemptSsid: ""
    property string wifiBackgroundStatus: ""
    property int wifiAttemptSerial: 0
    property int wifiActiveAttempt: 0
    property bool wifiScanPending: false
    property bool wifiConnectionPending: false
    property string wifiError: ""
    property string wifiConnectionState: "idle"
    property string wifiConnectionMessage: ""

    signal wifiStatus(string kind, string message)

    // QtObject has no default property, so timers are declared as properties.
    property Timer wifiConnectionTimeout: Timer {
        interval: 12000
        repeat: false
        onTriggered: {
            if (!root.wifiConnectionPending) return;
            root.wifiConnectionPending = false;
            root.wifiConnectionState = "failed";
            root.wifiError = "The Wi-Fi connection timed out. Try again.";
            root.wifiConnectionMessage = root.wifiError;
            root.wifiFlowStage = "failed";
            root.wifiStatus("wifi", "Connection failed");
        }
    }
    property Timer wifiSuccessTimer: Timer {
        interval: 900
        repeat: false
        onTriggered: {
            root.wifiConnectDialogVisible = false;
            root.wifiConnectPassword = "";
            root.wifiPasswordVisible = false;
            root.wifiFlowStage = "review";
            root.wifiConnectionState = "idle";
            root.wifiConnectionMessage = "";
        }
    }

    function applySnapshot(snapshot) {
        if (!Utils.applyBase(this, snapshot, providerName)) return false;
        var next = snapshot.data;
        // Provider events are partial updates. Preserve fields that are not
        // present instead of turning a valid full snapshot into empty lists.
        connectivity = Utils.stringOr(next.connectivity, connectivity);
        var previousSsid = connectedSsid;
        connectedSsid = Utils.stringOr(next.connected_ssid, connectedSsid);
        if (next.signal_strength !== undefined)
            signalStrength = Utils.nullableNumber(next.signal_strength);
        if (next.active_connection !== undefined)
            activeConnection = next.active_connection;
        if (next.ethernet !== undefined) ethernet = Utils.asArray(next.ethernet);
        if (next.available_wifi !== undefined) availableWifi = Utils.asArray(next.available_wifi);
        if (next.ipv4 !== undefined) ipv4 = Utils.asArray(next.ipv4);
        if (next.ipv6 !== undefined) ipv6 = Utils.asArray(next.ipv6);
        if (next.vpn !== undefined) vpn = Utils.asArray(next.vpn);
        if (next.metered !== undefined) metered = next.metered === true;
        if (next.networking_enabled !== undefined) networkingEnabled = next.networking_enabled === true;
        if (next.wifi_enabled !== undefined) wifiEnabled = Utils.nullableBool(next.wifi_enabled);
        if (next.wifi_hardware_enabled !== undefined) wifiHardwareEnabled = Utils.nullableBool(next.wifi_hardware_enabled);
        // The snapshot is the only place the flow learns it succeeded, so the
        // transition happens where the data actually changed.
        if (previousSsid !== connectedSsid) onConnectedSsidChanged();
        return true;
    }

    /// Resolve whichever attempt is outstanding after an SSID change.
    function onConnectedSsidChanged() {
        if (connectedSsid === "") return;
        if (wifiConnectionPending && connectedSsid === wifiConnectSsid) {
            wifiConnectionPending = false;
            wifiConnectionTimeout.stop();
            wifiError = "";
            wifiConnectionState = "connected";
            wifiFlowStage = "connected";
            wifiConnectionMessage = "Connected successfully.";
            wifiStatus("wifi", "Connected");
            wifiSuccessTimer.restart();
            return;
        }
        if (wifiBackgroundAttemptSsid !== "" && connectedSsid === wifiBackgroundAttemptSsid) {
            wifiBackgroundStatus = "Connected to " + wifiBackgroundAttemptSsid;
            wifiBackgroundAttemptSsid = "";
        }
    }

    /// The daemon rejected a connect attempt.
    function onConnectFailed(ssid, message) {
        if (ssid === wifiConnectSsid && (wifiConnectionPending || wifiFlowStage === "connecting")) {
            wifiConnectionPending = false;
            wifiConnectionTimeout.stop();
            wifiConnectionState = "failed";
            wifiError = String(message || "The Wi-Fi connection failed. Try again.");
            wifiConnectionMessage = wifiError;
            wifiFlowStage = "failed";
            wifiConnectDialogVisible = true;
            wifiStatus("wifi", "Connection failed");
            return;
        }
        if (ssid === wifiBackgroundAttemptSsid) {
            wifiBackgroundStatus = String(message || "Connection failed. Open the network to retry.");
            wifiBackgroundAttemptSsid = "";
        }
    }

    function openWifiConnect(networkInfo) {
        wifiConnectSsid = String(networkInfo.ssid || "").trim();
        wifiConnectSecurity = String(networkInfo.security || "");
        wifiConnectSaved = networkInfo.saved === true;
        wifiConnectPassword = "";
        wifiPasswordVisible = false;
        wifiError = "";
        wifiConnectionState = "idle";
        wifiConnectionMessage = "";
        wifiConnectionPending = false;
        wifiFlowStage = wifiConnectSaved || wifiConnectSecurity === "open" ? "review" : "credentials";
        wifiBackgroundAttemptSsid = "";
        wifiBackgroundStatus = "";
        wifiConnectionTimeout.stop();
        wifiSuccessTimer.stop();
        wifiConnectDialogVisible = wifiConnectSsid !== "";
    }

    function useAnotherWifiPassword() {
        wifiFlowStage = "credentials";
        wifiConnectionState = "idle";
        wifiError = "";
        wifiConnectionMessage = "Enter a new password for this saved network.";
        wifiPasswordVisible = false;
    }

    function submitWifiConnect(useSavedProfile) {
        if (!wifiConnectDialogVisible || wifiConnectSsid === "") return;
        if (!noxd || !noxd.connected) {
            wifiConnectionState = "failed";
            wifiError = "NoxFlow is not connected to the network service. Try again.";
            wifiConnectionMessage = wifiError;
            wifiFlowStage = "failed";
            return;
        }
        if (wifiConnectionPending) return;
        var savedProfile = useSavedProfile === true && wifiConnectSaved;
        if (!savedProfile && wifiConnectSecurity !== "open" && wifiConnectPassword === "") {
            wifiError = "Enter the Wi-Fi password to continue";
            wifiConnectionState = "failed";
            wifiFlowStage = "credentials";
            return;
        }
        wifiAttemptSerial += 1;
        wifiActiveAttempt = wifiAttemptSerial;
        var action = savedProfile
            ? { network_connect_saved: { ssid: wifiConnectSsid } }
            : { network_connect: { ssid: wifiConnectSsid, passphrase: wifiConnectPassword } };
        if (!noxd.runAction(action)) {
            wifiConnectionState = "failed";
            wifiError = "NoxFlow is not connected to the network service. Try again.";
            wifiConnectionMessage = wifiError;
            wifiFlowStage = "failed";
            return;
        }
        wifiStatus("wifi", "Connecting to " + wifiConnectSsid + "…");
        wifiConnectionPending = true;
        wifiConnectionState = "connecting";
        wifiFlowStage = "connecting";
        wifiConnectionMessage = savedProfile ? "Using the saved iwd profile…" : "Connecting securely…";
        wifiError = "";
        wifiBackgroundAttemptSsid = "";
        wifiBackgroundStatus = "";
        wifiConnectionTimeout.restart();
    }

    function cancelWifiConnect() {
        wifiConnectionTimeout.stop();
        wifiSuccessTimer.stop();
        if (wifiConnectionPending) {
            // The daemon keeps working after the dialog closes, so remember the
            // attempt and report its outcome as a banner instead of dropping it.
            wifiBackgroundAttemptSsid = wifiConnectSsid;
            wifiBackgroundStatus = "Connecting to " + wifiConnectSsid + "…";
        }
        wifiConnectionPending = false;
        wifiConnectionState = "idle";
        wifiConnectionMessage = "";
        wifiError = "";
        wifiConnectDialogVisible = false;
        wifiFlowStage = "review";
    }

    function forgetWifi(ssid) {
        if (!noxd || !noxd.connected) return;
        noxd.runAction({ network_forget: { ssid: ssid } });
        wifiStatus("wifi", "Forgetting " + ssid + "…");
        if (ssid === wifiConnectSsid) {
            wifiConnectDialogVisible = false;
            wifiConnectionPending = false;
        }
    }

    function dismissWifiBackground() {
        wifiBackgroundStatus = "";
        wifiBackgroundAttemptSsid = "";
    }
}