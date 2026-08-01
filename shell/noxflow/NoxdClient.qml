import QtQml
import Quickshell
import Quickshell.Io
import "Protocol.js" as Protocol
import "Fallbacks.js" as Fallbacks

QtObject {
    id: root

    // ── Public read-only state ──
    readonly property int protocolVersion: negotiatedVersion
    readonly property bool connected: socket.connected && phase === "subscribed"
    readonly property bool connecting: socket.connected && phase !== "subscribed"
    readonly property int eventCount: receivedEvents
    readonly property string lastEvent: eventDescription
    readonly property string lastError: errorText
    readonly property var providerHealth: health

    // Step 5 — Extended error visibility
    readonly property string connectionState: phase
    readonly property var lastFailedAction: failedAction
    readonly property int reconnectAttempt: reconnectCount
    readonly property int queuedActionCount: coalesceTimer.running ? Object.keys(coalesceSlots).length : 0

    // ── Signals (names must NOT clash with readonly property change signals) ──
    signal snapshotReceived(var snapshots)
    signal eventReceived(var event)
    signal connectionStateUpdated(string state)
    signal providerHealthUpdated(string provider, string status)

    // ── Socket path ──
    property string socketPath: {
        var runtime = Quickshell.env("XDG_RUNTIME_DIR");
        return (runtime ? runtime : "/tmp") + "/noxflow/noxd.sock";
    }

    // ── Private state ──
    property int negotiatedVersion: 0
    property int receivedEvents: 0
    property string eventDescription: "none"
    property string errorText: ""
    property var health: ({})
    // Event frames contain only changed fields. Keep the last complete
    // provider snapshot so models never lose arrays such as available_wifi
    // when a later event only updates connectivity or signal strength.
    property var snapshotCache: ({})
    property string phase: "idle"
    property int retryDelay: 250
    property int requestCounter: 0
    property var pendingRequests: ({})     // { id: { method, callback, errorCallback, deadline, metadata } }
    property var coalesceSlots: ({})       // { group: { action, params } }
    property string streamId: ""
    property string subscriptionId: ""
    property var failedAction: null
    property int reconnectCount: 0

    // ── Constants ──
    readonly property int requestTimeoutMs: 2000
    readonly property int coalesceDebounceMs: 80
    readonly property int maxCoalesceSlots: 32

    // ── Timer: sweep expired requests ──
    property Timer timeoutTimer: Timer {
        interval: 500
        repeat: true
        onTriggered: root.sweepTimeouts()
    }

    // ── Timer: flush coalesced actions ──
    property Timer coalesceTimer: Timer {
        repeat: false
        onTriggered: root.flushCoalesced()
    }

    // ── Timer: reconnect ──
    property Timer reconnectTimer: Timer {
        repeat: false
        onTriggered: root.connectNow()
    }

    // ── Socket ──
    property Socket socket: Socket {
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

    // ── Public API ──
    function start() {
        timeoutTimer.start();
        connectNow();
    }

    /// Send an action to the daemon. Returns true if accepted (queued or sent immediately).
    /// For backward compatibility: callers that ignore the return value are fine.
    function runAction(action) {
        if (!Protocol.isObject(action)) return false;
        return enqueueAction(action);
    }

    /// Write a setting value. Returns true if queued.
    function setSetting(key, value) {
        return sendRequest("set_setting", { key: key, value: value });
    }

    /// Read a setting. Calls callback(result) with the setting value result.
    function getSetting(key, callback, errorCallback) {
        return sendRequest("get_setting", { key: key }, callback, errorCallback);
    }

    /// Read all settings. Calls callback(result) with the settings map result.
    function getSettings(callback, errorCallback) {
        return sendRequest("get_settings", {}, callback, errorCallback);
    }

    // ── Connection management ──
    function connectNow() {
        reconnectTimer.stop();
        if (socket.connected) return;
        phase = "connecting";
        connectionStateUpdated("connecting");
        socket.path = socketPath;
        socket.connected = true;
    }

    function handleConnectionChange() {
        if (socket.connected) {
            console.info("noxd socket connected", socketPath);
            retryDelay = 250;
            reconnectCount = 0;
            negotiatedVersion = 0;
            eventDescription = "none";
            errorText = "";
            phase = "negotiating";
            connectionStateUpdated("negotiating");
            // Re-send pending requests that were disconnected mid-flight
            resendPendingRequests();
            sendRequest("get_version", undefined, handleVersion, handleVersionError);
        } else {
            console.warn("noxd socket disconnected", socketPath);
            phase = "disconnected";
            connectionStateUpdated("disconnected");
            subscriptionId = "";
            cancelPendingRequests("disconnected");
            scheduleReconnect();
        }
    }

    function handleVersionError(error) {
        failProtocol("daemon version negotiation failed: " + (error && error.message ? error.message : "timeout"));
    }

    function scheduleReconnect() {
        reconnectTimer.interval = retryDelay;
        reconnectTimer.start();
        retryDelay = Math.min(retryDelay * 2, 8000);
        reconnectCount += 1;
    }

    function handleSocketError(message) {
        console.error("noxd socket error", message);
        errorText = "socket: " + message;
        if (socket.connected) socket.connected = false;
    }

    // ── Request system (multi-request, timeouts, retry) ──
    /// Send a request to the daemon. Returns the request id string, or null if failed.
    /// callback(result) is called on success. errorCallback(code, message) on failure.
    function sendRequest(method, params, callback, errorCallback) {
        if (!socket.connected) {
            // Try fallback before failing
            if (tryFallback(method, params, callback, errorCallback)) return null;
            var errCb = errorCallback || defaultErrorCallback;
            errCb("disconnected", "daemon not connected");
            return null;
        }
        requestCounter += 1;
        var requestId = "shell-" + requestCounter;
        var request = {
            version: Protocol.protocolVersion,
            id: requestId,
            method: method
        };
        if (params !== undefined) request.params = params;

        pendingRequests[requestId] = {
            method: method,
            callback: callback || defaultCallback,
            errorCallback: errorCallback || defaultErrorCallback,
            deadline: Date.now() + requestTimeoutMs,
            metadata: { method: method, params: params }
        };

        socket.write(JSON.stringify(request) + "\n");
        socket.flush();
        return requestId;
    }

    function defaultCallback(result) {
        // no-op
    }

    function defaultErrorCallback(code, message) {
        console.warn("noxd request failed:", code, message);
        errorText = message || String(code);
    }

    function sweepTimeouts() {
        var now = Date.now();
        var keys = Object.keys(pendingRequests);
        for (var i = 0; i < keys.length; i++) {
            var id = keys[i];
            var entry = pendingRequests[id];
            if (entry && now >= entry.deadline) {
                // Request timed out
                console.warn("noxd request timed out:", id, entry.method);
                var ecb = entry.errorCallback;
                delete pendingRequests[id];

                // Retry policy: retry once for idempotent requests
                if (canRetry(entry.method, entry.metadata)) {
                    entry.retryCount = (entry.retryCount || 0) + 1;
                    if (entry.retryCount <= 1) {
                        entry.deadline = now + requestTimeoutMs;
                        pendingRequests[id] = entry;
                        // Re-send the request
                        var request = {
                            version: Protocol.protocolVersion,
                            id: id,
                            method: entry.method
                        };
                        if (entry.metadata && entry.metadata.params !== undefined)
                            request.params = entry.metadata.params;
                        if (socket.connected) {
                            socket.write(JSON.stringify(request) + "\n");
                            socket.flush();
                        }
                        continue;  // keep sweeping other entries
                    }
                }

                failedAction = { action: entry.method, error: "timeout", timestamp: now };
                ecb("timeout", "request timed out after " + requestTimeoutMs + "ms");
            }
        }
    }

    function canRetry(method, metadata) {
        // Never retry destructive actions
        if (method === "run_action" && metadata && metadata.params && metadata.params.action) {
            var actionKey = Object.keys(metadata.params.action)[0];
            if (actionKey === "reboot" || actionKey === "power_off"
                || actionKey === "suspend" || actionKey === "lock") {
                return false;
            }
        }
        return true;
    }

    function cancelPendingRequests(reason) {
        var now = Date.now();
        var keys = Object.keys(pendingRequests);
        for (var i = 0; i < keys.length; i++) {
            var id = keys[i];
            var entry = pendingRequests[id];
            if (entry) {
                failedAction = { action: entry.method, error: reason, timestamp: now };
                entry.errorCallback(reason, "disconnected before response");
            }
        }
        pendingRequests = {};
    }

    function resendPendingRequests() {
        // Re-send any requests that were waiting mid-flight
        var keys = Object.keys(pendingRequests);
        for (var i = 0; i < keys.length; i++) {
            var id = keys[i];
            var entry = pendingRequests[id];
            if (entry && entry.metadata) {
                var request = {
                    version: Protocol.protocolVersion,
                    id: id,
                    method: entry.method
                };
                if (entry.metadata.params !== undefined)
                    request.params = entry.metadata.params;
                socket.write(JSON.stringify(request) + "\n");
                socket.flush();
            }
        }
    }

    // ── Action coalescing (Step 4) ──
    function enqueueAction(action) {
        var actionKey = Object.keys(action)[0];
        var actionParams = action[actionKey];

        // Determine coalesce group
        var group = coalesceGroup(actionKey, actionParams);

        if (group) {
            // Coalescable: store latest value, schedule flush
            coalesceSlots[group] = { actionKey: actionKey, params: actionParams };
            if (!coalesceTimer.running) {
                coalesceTimer.interval = coalesceDebounceMs;
                coalesceTimer.start();
            }
            return true;
        }

        // Non-coalescable: send immediately
        return doSendAction(actionKey, actionParams);
    }

    function flushCoalesced() {
        var slots = coalesceSlots;
        coalesceSlots = {};
        var keys = Object.keys(slots);
        for (var i = 0; i < keys.length; i++) {
            var slot = slots[keys[i]];
            doSendAction(slot.actionKey, slot.params);
        }
    }

    function coalesceGroup(actionKey, params) {
        if (actionKey === "brightness_set" || actionKey === "brightness_adjust")
            return "brightness";
        if (actionKey === "audio_set_volume" || actionKey === "audio_adjust_volume") {
            var target = (params && params.target) || "output";
            return "volume::" + target;
        }
        if (actionKey === "network_refresh")
            return "refresh::network";
        return null; // not coalesced
    }

    function doSendAction(actionKey, params) {
        var actionPayload = {};
        actionPayload[actionKey] = params || {};
        return sendRequest("run_action", { action: actionPayload });
    }

    // ── Fallback system (Step 7) ──
    function tryFallback(method, params, callback, errorCallback) {
        if (method !== "run_action" || !params || !params.action) return false;
        var actionKey = Object.keys(params.action)[0];
        var actionParams = params.action[actionKey];

        var fallback = Fallbacks.get(actionKey);
        if (!fallback) return false;

        console.log("noxd: using fallback for", actionKey);
        errorText = "daemon unavailable; using fallback for " + actionKey;
        failedAction = { action: actionKey, error: "fallback", timestamp: Date.now() };

        try {
            fallback(actionParams);
            if (callback) callback({ type: "action_accepted", data: { action: params.action } });
            return true;
        } catch (err) {
            console.error("noxd: fallback failed for", actionKey, err);
            failedAction = { action: actionKey, error: String(err), timestamp: Date.now() };
            if (errorCallback) errorCallback("fallback_failed", String(err));
            return true; // we tried, don't also send to daemon
        }
    }

    // ── Protocol handshake ──
    function handleVersion(result) {
        var info = Protocol.responseData(result, "version");
        if (!info || info.protocol_version !== Protocol.protocolVersion) {
            failProtocol("daemon did not negotiate protocol v1");
            return;
        }
        negotiatedVersion = info.protocol_version;
        phase = "state";
        connectionStateUpdated("state");
        sendRequest("get_state", undefined, handleState, function(error, msg) {
            failProtocol("get_state failed: " + msg);
        });
    }

    function handleState(result) {
        var state = Protocol.responseData(result, "state");
        if (!state || !Protocol.isObject(state.providers)) {
            failProtocol("daemon returned malformed initial state");
            return;
        }
        // Load settings if present
        if (state.settings) emitSettingsEvents(state.settings);
        publishSnapshots(state.providers);
        phase = "subscribing";
        connectionStateUpdated("subscribing");
        sendRequest("subscribe", { providers: [], event_types: [] }, handleSubscription, function(error, msg) {
            failProtocol("subscribe failed: " + msg);
        });
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
        connectionStateUpdated("subscribed");
        console.info("noxd IPC subscribed", streamId, subscriptionId);
    }

    // ── Frame handling ──
    function handleFrame(text) {
        var parsed = Protocol.validateFrame(String(text));
        if (!parsed.ok) { errorText = parsed.error; return; }
        if (parsed.kind === "response") handleResponse(parsed.value);
        else handleEvent(parsed.value);
    }

    function handleResponse(response) {
        var entry = pendingRequests[response.id];
        if (!entry) {
            // Could be a timed-out response — ignore
            return;
        }
        delete pendingRequests[response.id];
        if (response.error !== undefined) {
            var errMsg = response.error.message || "daemon request failed";
            console.error("noxd request failed", response.id, errMsg);
            errorText = errMsg;
            failedAction = { action: entry.method, error: errMsg, timestamp: Date.now() };
            entry.errorCallback(response.error.code || "error", errMsg);
            return;
        }
        entry.callback(response.result);
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

        // Handle setting_changed events by emitting them
        if (event.provider === "settings" && event.event_type === "changed") {
            // Pass through to models if they handle it
        }

        updateHealth(snapshot);
        eventReceived(event);
        var updates = {};
        updates[event.provider] = snapshot;
        publishSnapshots(updates);
    }

    function emitSettingsEvents(settings) {
        if (!settings || typeof settings !== "object") return;
        var keys = Object.keys(settings);
        for (var i = 0; i < keys.length; i++) {
            // Emit synthetic events for initial settings load
            var fakeEvent = {
                version: 1,
                timestamp: Math.floor(Date.now() / 1000),
                stream_id: streamId,
                sequence: 0,
                provider: "settings",
                event_type: "changed",
                schema_version: 1,
                data: { key: keys[i], value: settings[keys[i]] }
            };
            // Don't send to models, just let the settings system know
        }
    }

    // ── Snapshot dispatching ──
    function publishSnapshots(snapshots) {
        var mergedSnapshots = {};
        for (var provider in snapshots) {
            var snapshot = snapshots[provider];
            if (!Protocol.providerSnapshot(snapshot)) continue;
            var previous = snapshotCache[provider];
            var merged = snapshot;
            if (previous && previous.status === "available" && snapshot.status === "available"
                    && previous.data && snapshot.data) {
                var data = {};
                for (var key in previous.data) data[key] = previous.data[key];
                for (var changedKey in snapshot.data) data[changedKey] = snapshot.data[changedKey];
                merged = { provider: snapshot.provider, status: snapshot.status, data: data };
            }
            snapshotCache[provider] = merged;
            mergedSnapshots[provider] = merged;
            updateHealth(merged);
        }
        root.snapshotReceived(mergedSnapshots);
    }

    function updateHealth(snapshot) {
        var prev = health[snapshot.provider];
        var next = {};
        for (var k in health) next[k] = health[k];
        next[snapshot.provider] = snapshot.status;
        health = next;
        if (prev !== snapshot.status) {
            providerHealthUpdated(snapshot.provider, snapshot.status);
        }
    }

    // ── Error handling ──
    function failProtocol(message) {
        console.error("noxd protocol failure", message);
        errorText = message;
        phase = "disconnected";
        connectionStateUpdated("disconnected");
        cancelPendingRequests("protocol_failure");
        if (socket.connected) socket.connected = false;
    }
}
