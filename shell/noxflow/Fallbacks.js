.pragma library

// Fallback implementations for essential actions when noxd is unreachable.
// Each function receives the action params object.
// Logging is handled by the caller (NoxdClient.qml).

function fallbackWorkspaceFocus(params) {
    var ws = params && (params.workspace || params.id || "");
    if (!ws) throw new Error("workspace_focus requires a workspace identifier");
    exec("hyprctl", ["dispatch", "workspace", String(ws)]);
}

function fallbackWorkspaceCycle(params) {
    var delta = params && params.delta;
    if (delta === undefined || delta === null) throw new Error("workspace_cycle requires a delta");
    var dir = delta > 0 ? "+1" : "-1";
    exec("hyprctl", ["dispatch", "workspace", dir]);
}

function fallbackLock() {
    exec("loginctl", ["lock-session"]);
}

function fallbackSuspend() {
    exec("systemctl", ["suspend"]);
}

function exec(cmd, args) {
    // Use Quickshell.exec for async execution
    // We access it from the global scope since this is called from Qt context
    try {
        Quickshell.exec(cmd, args);
    } catch (e) {
        // Fall back to single-command form
        try {
            Quickshell.exec(cmd + " " + args.join(" "));
        } catch (e2) {
            throw new Error("fallback command failed: " + cmd + " " + args.join(" ") + " — " + e2);
        }
    }
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
