.pragma library

var protocolVersion = 1;
var providers = ["hyprland", "audio", "brightness", "power", "network", "bluetooth", "media", "notifications"];

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
