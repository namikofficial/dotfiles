.pragma library

var MAX_ENTRIES = 5;

function record(history, window) {
    if (!window || typeof window !== "object") return history || [];
    var address = String(window.address || "");
    if (!/^0x[0-9a-f]+$/i.test(address)) return history || [];

    var rawApp = String(window.application_id || window.class || window.appid || window.initialClass || "").trim();
    var appParts = rawApp.split(".");
    var app = appParts[appParts.length - 1].replace(/[-_]+/g, " ");
    if (app) app = app.charAt(0).toUpperCase() + app.slice(1);

    var workspace = window.workspace;
    var workspaceId = workspace && typeof workspace === "object"
        ? String(workspace.id !== undefined ? workspace.id : workspace.name || "")
        : String(workspace || "");
    var entry = {
        address: address,
        app: app || "Window",
        title: String(window.title || window.initialTitle || "").trim(),
        workspaceId: workspaceId
    };

    var next = [entry];
    var previous = Array.isArray(history) ? history : [];
    for (var i = 0; i < previous.length && next.length < MAX_ENTRIES; i++) {
        if (!previous[i] || String(previous[i].address || "") === address
                || !/^0x[0-9a-f]+$/i.test(String(previous[i].address || ""))) continue;
        next.push(previous[i]);
    }
    return next;
}

