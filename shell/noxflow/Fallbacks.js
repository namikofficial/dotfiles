.pragma library

// Fallback implementations for essential actions when noxd is unreachable.
// Each function receives the action params object and an `exec` function
// supplied by the caller. Logging is handled by the caller (NoxdClient.qml).
//
// A `.pragma library` file has no QML context, so it cannot reach Quickshell
// directly. The previous version called `Quickshell.exec`, which does not
// exist in Quickshell 0.3.1 — every fallback silently threw, so a daemon
// outage turned workspace switching, lock and suspend into dead buttons.

function fallbackWorkspaceFocus(params, exec) {
    var ws = params && (params.workspace || params.id || "");
    if (!ws) throw new Error("workspace_focus requires a workspace identifier");
    exec("hyprctl", ["dispatch", "workspace", String(ws)]);
}

function fallbackWorkspaceCycle(params, exec) {
    var delta = params && params.delta;
    if (delta === undefined || delta === null) throw new Error("workspace_cycle requires a delta");
    var dir = delta > 0 ? "+1" : "-1";
    exec("hyprctl", ["dispatch", "workspace", dir]);
}

function fallbackLock(params, exec) {
    exec("loginctl", ["lock-session"]);
}

function fallbackSuspend(params, exec) {
    exec("systemctl", ["suspend"]);
}

// Registry: action name → fallback function
// Only includes actions that have safe system-level fallbacks.
var registry = {
    "workspace_focus": fallbackWorkspaceFocus,
    "workspace_cycle": fallbackWorkspaceCycle,
    "lock": fallbackLock,
    "suspend": fallbackSuspend
};

function get(actionName) {
    return registry[actionName] || null;
}