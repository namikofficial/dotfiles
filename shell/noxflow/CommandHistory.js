.pragma library

var MAX_COMMANDS = 8;

function cleanValue(value) {
    if (value === undefined || value === null) return "";
    var text = String(value).trim();
    if (text.length === 0 || text.length > 256 || /[\u0000-\u001f\u007f]/.test(text)) return "";
    return text;
}

function encodeValue(value) {
    var text = cleanValue(value);
    return text === "" ? "" : encodeURIComponent(text);
}

function decodeValue(value) {
    try { return decodeURIComponent(value); }
    catch (e) { return ""; }
}

function validKey(key) {
    if (key === "settings" || key === "clipboard" || key === "screenshot") return true;
    if (typeof key !== "string") return false;

    var parts = key.split(":");
    if (parts.length === 2 && parts[0] === "app") {
        var desktopId = decodeValue(parts[1]);
        return /^[A-Za-z0-9][A-Za-z0-9_.+-]*\.desktop$/.test(desktopId);
    }
    if (parts.length === 2 && parts[0] === "program") {
        var program = decodeValue(parts[1]);
        return /^[A-Za-z][A-Za-z0-9_.-]{0,63}$/.test(program);
    }
    if (parts.length === 3 && parts[0] === "project") {
        var projectId = decodeValue(parts[1]);
        return cleanValue(projectId) !== "" && ["resume", "edit", "shell", "tmux"].indexOf(parts[2]) >= 0;
    }
    return false;
}

function keyFor(item) {
    if (!item || typeof item !== "object") return "";
    var params = item.actionParams || {};
    var encoded;

    if (item.action === "launch") {
        var desktopId = cleanValue(params.desktopId);
        if (!/^[A-Za-z0-9][A-Za-z0-9_.+-]*\.desktop$/.test(desktopId)) return "";
        encoded = encodeValue(desktopId);
        return encoded ? "app:" + encoded : "";
    }
    if (item.action === "launchProgram") {
        var program = cleanValue(params.program);
        if (!/^[A-Za-z][A-Za-z0-9_.-]{0,63}$/.test(program)) return "";
        encoded = encodeValue(program);
        return encoded ? "program:" + encoded : "";
    }
    if (item.action === "resume_project" || item.action === "project_action") {
        var projectId = encodeValue(params.id);
        if (!projectId) return "";
        var operation = item.action === "resume_project" ? "resume" : String(params.command || "");
        var key = "project:" + projectId + ":" + operation;
        return validKey(key) ? key : "";
    }
    if (item.action === "open_settings") return "settings";
    if (item.action === "open_clipboard") return "clipboard";
    if (item.action === "screenshot") return "screenshot";
    return "";
}

function normalize(keys) {
    if (!Array.isArray(keys)) return [];
    var normalized = [];
    var seen = {};
    for (var i = 0; i < keys.length && normalized.length < MAX_COMMANDS; i++) {
        var key = keys[i];
        if (typeof key !== "string" || !validKey(key) || seen[key]) continue;
        seen[key] = true;
        normalized.push(key);
    }
    return normalized;
}

function position(keys, item) {
    var key = keyFor(item);
    if (!key) return -1;
    var safeKeys = normalize(keys);
    for (var i = 0; i < safeKeys.length; i++) {
        if (safeKeys[i] === key) return i;
    }
    return -1;
}

