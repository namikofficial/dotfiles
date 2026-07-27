import QtQml
import Quickshell
import Quickshell.Io
import "Protocol.js" as Protocol

QtObject {
    id: root

    readonly property int protocolVersion: negotiatedVersion
    readonly property bool connected: socket.connected && phase === "subscribed"
    readonly property bool connecting: socket.connected && phase !== "subscribed"
    readonly property int eventCount: receivedEvents
    readonly property string lastEvent: eventDescription
    readonly property string lastError: errorText
    readonly property var providerHealth: health
    property string socketPath: {
        var runtime = Quickshell.env("XDG_RUNTIME_DIR");
        return (runtime ? runtime : "/tmp") + "/noxflow/noxd.sock";
    }
    signal snapshotReceived(var snapshots)
    signal eventReceived(var event)

    property int negotiatedVersion: 0
    property int receivedEvents: 0
    property string eventDescription: "none"
    property string errorText: ""
    property var health: ({})
    property string phase: "idle"
    property int retryDelay: 250
    property int requestCounter: 0
    property var pending: null
    property string streamId: ""
    property string subscriptionId: ""

    Timer { id: reconnectTimer; repeat: false; onTriggered: root.connectNow() }

    Socket {
        id: socket
        path: root.socketPath
        connected: false
        parser: SplitParser {
            splitMarker: "\n"
            onRead: message => root.handleFrame(message)
        }
        onConnectedChanged: root.handleConnectionChange()
        onError: error => root.handleSocketError(String(error))
    }

    function start() { connectNow(); }

    function connectNow() {
        reconnectTimer.stop();
        if (socket.connected) return;
        phase = "connecting";
        socket.path = socketPath;
        socket.connected = true;
    }

    function handleConnectionChange() {
        if (socket.connected) {
            retryDelay = 250;
            negotiatedVersion = 0;
            eventDescription = "none";
            errorText = "";
            phase = "negotiating";
            sendRequest("get_version", undefined, handleVersion);
        } else {
            phase = "disconnected";
            pending = null;
            subscriptionId = "";
            scheduleReconnect();
        }
    }

    function scheduleReconnect() {
        reconnectTimer.interval = retryDelay;
        reconnectTimer.start();
        retryDelay = Math.min(retryDelay * 2, 8000);
    }

    function handleSocketError(message) {
        errorText = "socket: " + message;
        if (socket.connected) socket.connected = false;
    }

    function sendRequest(method, params, callback) {
        if (!socket.connected || pending !== null) return false;
        requestCounter += 1;
        var request = { version: Protocol.protocolVersion, id: "shell-" + requestCounter, method: method };
        if (params !== undefined) request.params = params;
        pending = { id: request.id, callback: callback };
        socket.write(JSON.stringify(request) + "\n");
        socket.flush();
        return true;
    }

    function handleVersion(result) {
        var info = Protocol.responseData(result, "version");
        if (!info || info.protocol_version !== Protocol.protocolVersion) {
            failProtocol("daemon did not negotiate protocol v1");
            return;
        }
        negotiatedVersion = info.protocol_version;
        phase = "state";
        sendRequest("get_state", undefined, handleState);
    }

    function handleState(result) {
        var state = Protocol.responseData(result, "state");
        if (!state || !Protocol.isObject(state.providers)) {
            failProtocol("daemon returned malformed initial state");
            return;
        }
        publishSnapshots(state.providers);
        phase = "subscribing";
        sendRequest("subscribe", { providers: [], event_types: [] }, handleSubscription);
    }

    function handleSubscription(result) {
        var subscription = Protocol.responseData(result, "subscription");
        if (!subscription || typeof subscription.subscription_id !== "string"
                || typeof subscription.stream_id !== "string" || !Protocol.isObject(subscription.snapshots)) {
            failProtocol("daemon returned malformed subscription acknowledgement");
            return;
        }
        streamId = subscription.stream_id;
        subscriptionId = subscription.subscription_id;
        publishSnapshots(subscription.snapshots);
        phase = "subscribed";
    }

    function handleFrame(text) {
        var parsed = Protocol.validateFrame(String(text));
        if (!parsed.ok) { errorText = parsed.error; return; }
        if (parsed.kind === "response") handleResponse(parsed.value);
        else handleEvent(parsed.value);
    }

    function handleResponse(response) {
        if (!pending || response.id !== pending.id) { errorText = "unexpected response id"; return; }
        var callback = pending.callback;
        pending = null;
        if (response.error !== undefined) {
            errorText = response.error.message || "daemon request failed";
            if (phase !== "subscribed") failProtocol(errorText);
            return;
        }
        callback(response.result);
    }

    function handleEvent(event) {
        if (Protocol.providers.indexOf(event.provider) < 0) return;
        if (event.stream_id !== streamId) {
            errorText = "daemon stream changed; reconnecting";
            socket.connected = false;
            return;
        }
        receivedEvents += 1;
        eventDescription = event.provider + ":" + event.event_type + " (#" + event.sequence + ")";
        var snapshot = { provider: event.provider, status: "available", data: event.data };
        updateHealth(snapshot);
        eventReceived(event);
        var updates = {};
        updates[event.provider] = snapshot;
        publishSnapshots(updates);
    }

    function publishSnapshots(snapshots) {
        for (var provider in snapshots) {
            if (Protocol.providerSnapshot(snapshots[provider])) updateHealth(snapshots[provider]);
        }
        root.snapshotReceived(snapshots);
    }

    function updateHealth(snapshot) {
        var next = Object.assign({}, health);
        next[snapshot.provider] = snapshot.status;
        health = next;
    }

    function failProtocol(message) {
        errorText = message;
        phase = "disconnected";
        if (socket.connected) socket.connected = false;
    }
}
