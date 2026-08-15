function value(value, primary, secondary, fallback) {
    if (value && value[primary] !== undefined && value[primary] !== null) return value[primary];
    if (value && secondary && value[secondary] !== undefined && value[secondary] !== null) return value[secondary];
    return fallback;
}

function workspaceId(workspace) {
    var id = workspace && typeof workspace === "object" ? value(workspace, "name", "id", "") : workspace;
    return id === undefined || id === null ? "" : String(id);
}

function applicationName(window) {
    if (!window || typeof window !== "object") return "";
    var raw = String(value(window, "application_id", "class", value(window, "appid", "initialClass", ""))).trim();
    if (!raw) return "";
    var pieces = raw.split(".");
    var label = pieces[pieces.length - 1].replace(/[-_]+/g, " ").trim();
    return label ? label.charAt(0).toUpperCase() + label.slice(1) : raw;
}

function windowTitle(window) {
    if (!window || typeof window !== "object") return "";
    return String(value(window, "title", "initialTitle", "")).trim();
}

function activeWindowMatches(workspaceName, monitorName, focusedMonitor, activeWorkspace, window) {
    if (!window || typeof window !== "object") return false;
    var windowWorkspace = workspaceId(window.workspace);
    if (windowWorkspace) return windowWorkspace === String(workspaceName);
    return String(monitorName || "") === String(focusedMonitor || "")
        && workspaceId(activeWorkspace) === String(workspaceName);
}

function tooltip(workspaceName, active, occupied, app, title) {
    var parts = ["Workspace " + workspaceName];
    if (active) parts.push("active");
    else if (occupied) parts.push("occupied");
    if (app) parts.push(app);
    if (title && title !== app) parts.push(title);
    return parts.join(" · ");
}
