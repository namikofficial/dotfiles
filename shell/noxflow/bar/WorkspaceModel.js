// WorkspaceModel.js — the bar's workspace derivation, extracted from Bar.qml.
//
// Bar.qml carried ~70 lines of workspace derivation inline: scanning
// hyprland workspaces and windows, filtering special: and cross-monitor
// entries, sorting numerically-then-lexically, and computing per-workspace
// active/occupied/urgent. It is pure logic with no QML dependency, so it
// belongs in a module — and can then be unit tested without a session.

.pragma library

function value(object, primary, secondary, fallback) {
    if (object && object[primary] !== undefined && object[primary] !== null) return object[primary];
    if (object && secondary && object[secondary] !== undefined && object[secondary] !== null) return object[secondary];
    return fallback;
}

function workspaceId(workspace) {
    if (workspace === null || workspace === undefined) return "";
    if (typeof workspace !== "object") return String(workspace);
    var id = value(workspace, "name", "id", "");
    return id === undefined || id === null ? "" : String(id);
}

/// The monitor record this bar is showing, or null.
function findMonitor(monitors, monitorName) {
    for (var i = 0; i < monitors.length; i++) {
        if (String(monitors[i].name || "") === monitorName) return monitors[i];
    }
    return null;
}

/// The workspace record for `name` on this monitor, or null.
function record(workspaces, name, monitorName) {
    for (var i = 0; i < workspaces.length; i++) {
        var item = workspaces[i];
        if (!item) continue;
        if (String(item.name || item.id) !== name) continue;
        if (String(item.monitor || "") !== monitorName) continue;
        return item;
    }
    return null;
}

function monitorId(monitor) {
    return monitor && monitor.id !== undefined ? Number(monitor.id) : -1;
}

/// The workspace the monitor is currently showing, honouring an optimistic
/// pending selection so the pill highlights before the compositor confirms it.
function activeWorkspace(hyprland, monitor, monitorName, pendingWorkspace) {
    if (pendingWorkspace !== undefined && pendingWorkspace !== null && pendingWorkspace !== "")
        return pendingWorkspace;
    if (hyprland.focusedMonitor === monitorName && hyprland.activeWorkspace)
        return workspaceId(hyprland.activeWorkspace);
    return workspaceId(monitor ? value(monitor, "activeWorkspace", "active_workspace", null) : null);
}

/// Workspaces to show for this monitor, in display order.
///
/// A workspace appears when it is occupied, when it is the active one, or when
/// a window on it names it. `special:` workspaces and other monitors' entries
/// are excluded.
function build(hyprland, monitorName, activeName) {
    var entries = [];

    function push(name) {
        if (entries.indexOf(name) < 0) entries.push(name);
    }

    for (var i = 0; i < hyprland.workspaces.length; i++) {
        var workspace = hyprland.workspaces[i];
        if (!workspace) continue;
        var name = String(workspace.name !== undefined && workspace.name !== null ? workspace.name : workspace.id);
        if (!name || name.indexOf("special:") === 0) continue;
        if (monitorName !== "" && String(workspace.monitor || "") !== monitorName) continue;
        if (Number(workspace.windows || 0) <= 0 && name !== activeName) continue;
        push(name);
    }

    for (var k = 0; k < hyprland.windows.length; k++) {
        var client = hyprland.windows[k];
        if (!client || !client.workspace) continue;
        var clientWorkspace = client.workspace;
        var clientName = String(clientWorkspace.name !== undefined && clientWorkspace.name !== null
            ? clientWorkspace.name : clientWorkspace.id);
        if (!clientName || clientName.indexOf("special:") === 0) continue;
        var clientMonitor = client.monitorName !== undefined
            ? String(client.monitorName)
            : String(client.monitor !== undefined ? client.monitor : "");
        if (monitorName !== "" && clientMonitor !== "" && clientMonitor !== monitorName
            && Number(client.monitor) !== monitorId(findMonitor(hyprland.monitors, monitorName)))
            continue;
        push(clientName);
    }

    if (activeName !== undefined && activeName !== "" && entries.indexOf(activeName) < 0)
        push(activeName);

    entries.sort(function (a, b) {
        var na = parseInt(a, 10), nb = parseInt(b, 10);
        if (!isNaN(na) && !isNaN(nb)) return na - nb;
        if (!isNaN(na)) return -1;
        if (!isNaN(nb)) return 1;
        return a < b ? -1 : a > b ? 1 : 0;
    });
    return entries;
}

function occupied(hyprland, name, monitorName) {
    if (!record(hyprland.workspaces, name, monitorName)) return false;
    for (var i = 0; i < hyprland.windows.length; i++) {
        var client = hyprland.windows[i];
        if (client && workspaceId(client.workspace) === name) return true;
    }
    return false;
}

function urgent(hyprland, name, monitorName) {
    if (!record(hyprland.workspaces, name, monitorName)) return false;
    for (var i = 0; i < hyprland.windows.length; i++) {
        var client = hyprland.windows[i];
        if (!client) continue;
        if (workspaceId(client.workspace) !== name) continue;
        if (hyprland.urgentWindows.indexOf(String(client.address || "")) >= 0) return true;
    }
    return false;
}

/// How many urgent windows this monitor is showing. Drives the bar's urgent
/// styling.
function urgentCount(hyprland, monitorName) {
    var count = 0;
    for (var i = 0; i < hyprland.windows.length; i++) {
        var client = hyprland.windows[i];
        if (!client) continue;
        if (hyprland.urgentWindows.indexOf(String(client.address || "")) < 0) continue;
        if (record(hyprland.workspaces, workspaceId(client.workspace), monitorName)) count++;
    }
    return count;
}

/// Reject anything that is not a plain workspace identifier before it reaches
/// a shell command. This string is interpolated into `hyprctl eval`, so a
/// malformed value would be a command-injection vector, not just a typo.
function isValidTarget(name) {
    var target = String(name === undefined || name === null ? "" : name).trim();
    if (!target || target.indexOf("special:") === 0) return false;
    return /^[0-9A-Za-z_-]+$/.test(target);
}

/// The `hyprctl eval` argument for focusing or cycling a workspace.
function dispatchArgument(target) {
    return "hl.dispatch(hl.dsp.focus({ workspace = \"" + target + "\" }))";
}