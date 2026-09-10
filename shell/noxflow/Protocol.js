.pragma library

var protocolVersion = 1;
// Provider event allowlist.
//
// The QML client only subscribes to providers whose events have a real,
// observable consumer in the shell. Each entry must correspond to:
//   1. A registered provider on the daemon side (core/noxd/src/main.rs).
//   2. A consumer that wires `applyEvent` / `applySnapshot` from this client
//      (typically via the daemonClient Connections in shell.qml).
//
// "transfer" is included because core/noxd/src/providers/transfer.rs publishes
// `discovery` and `sessions` events that TransferModel.qml consumes in
// shell.qml's `onEventReceived`. "notifications" is included because
// NotificationModel.qml consumes its own snapshot fan-out via applySnapshot
// (the provider is daemon-typed for state, even though the model is
// shell-owned).
//
// "settings" is intentionally NOT in this allowlist. Settings changes are
// delivered through the explicit set_setting / get_setting requests and the
// SettingUpdated response (see NoxdClient.qml setSetting / getSetting). No QML
// component consumes settings provider events today, and adding "settings"
// here would route SettingChangedEvent envelopes into `onEventReceived` with
// no handler — silently discarded and raising the question of why the event
// exists at all. If a future surface needs live settings updates, add it here
// AND wire a consumer in shell.qml on the same change.
var providers = ["hyprland", "audio", "brightness", "power", "network", "bluetooth", "media", "notifications", "transfer"];

function isAllowedProvider(name) {
    if (typeof name !== "string") return false;
    return providers.indexOf(name) >= 0;
}

function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function responseData(response, expectedType) {
    if (!isObject(response) || response.type !== expectedType || !isObject(response.data)) return null;
    return response.data;
}

function providerSnapshot(snapshot) {
    return isObject(snapshot) && typeof snapshot.provider === "string"
            && typeof snapshot.status === "string" && isObject(snapshot.data);
}

function validateFrame(text) {
    var value;
    try { value = JSON.parse(text); } catch (error) { return { ok: false, error: "invalid JSON" }; }
    if (!isObject(value) || value.version !== protocolVersion) {
        return { ok: false, error: "unsupported or missing protocol version" };
    }
    if (typeof value.id === "string") {
        if ((value.result === undefined) === (value.error === undefined)) {
            return { ok: false, error: "response must contain exactly one result or error" };
        }
        if (value.error !== undefined && (!isObject(value.error) || typeof value.error.code !== "string")) {
            return { ok: false, error: "malformed response error" };
        }
        if (value.result !== undefined && !isObject(value.result)) {
            return { ok: false, error: "malformed response result" };
        }
        return { ok: true, kind: "response", value: value };
    }
    if (typeof value.timestamp !== "number" || typeof value.stream_id !== "string"
            || typeof value.sequence !== "number" || typeof value.provider !== "string"
            || typeof value.event_type !== "string" || typeof value.schema_version !== "number"
            || !isObject(value.data)) {
        return { ok: false, error: "malformed event envelope" };
    }
    return { ok: true, kind: "event", value: value };
}
