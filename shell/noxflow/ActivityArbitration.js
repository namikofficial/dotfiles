var MODES = ["idle", "activity", "dashboard", "launcher", "calendar"];
var DASHBOARDS = ["workspace", "health", "connectivity", "audio-power",
    "notification-preview", "updates", "sync", "provider-health"];
var CRITICAL_KINDS = ["battery-warning", "network-warning", "recording", "timer"];

function clone(value) {
    if (value === null || typeof value !== "object") return value;
    if (Array.isArray(value)) return value.map(clone);
    var copy = {};
    for (var key in value) if (Object.prototype.hasOwnProperty.call(value, key)) copy[key] = clone(value[key]);
    return copy;
}

function normalizeActivity(input, fallbackMonitor) {
    var source = input || {};
    var maximum = Number(source.maximum);
    var value = Number(source.value);
    return {
        id: String(source.id || (String(source.kind || "activity") + "-" + String(source.timestamp || Date.now()))),
        kind: String(source.kind || "activity"),
        severity: String(source.severity || "info"),
        priority: Math.max(0, Number(source.priority) || 0),
        title: String(source.title || ""),
        detail: String(source.detail || ""),
        value: isFinite(value) ? value : 0,
        maximum: isFinite(maximum) && maximum > 0 ? maximum : 1,
        timeoutMs: Math.max(1, Number(source.timeoutMs) || 2000),
        targetPanel: String(source.targetPanel || ""),
        targetSection: String(source.targetSection || ""),
        monitor: String(source.monitor || fallbackMonitor || ""),
        timestamp: Number(source.timestamp) || Date.now()
    };
}

function newState() {
    return {
        mode: "idle",
        targetMonitor: "",
        dashboard: null,
        pin: null,
        activity: null,
        interrupted: null,
        queue: [],
        focusOwner: ""
    };
}

function openLayer(state, mode, monitor) {
    if (mode !== "launcher" && mode !== "calendar") return state;
    var next = clone(state);
    next.mode = mode;
    next.targetMonitor = String(monitor || next.targetMonitor || "");
    next.focusOwner = mode;
    return next;
}

function closeLayer(state) {
    var next = clone(state);
    if (next.mode === "launcher" || next.mode === "calendar") next.focusOwner = "";
    if (next.activity) next.mode = "activity";
    else if (next.pin || next.dashboard) next.mode = "dashboard";
    else next.mode = "idle";
    return next;
}

function showDashboard(state, route) {
    if (!route || DASHBOARDS.indexOf(route.kind) < 0) return state;
    var next = clone(state);
    next.dashboard = clone(route);
    next.targetMonitor = String(route.monitor || next.targetMonitor || "");
    if (next.mode !== "launcher" && next.mode !== "calendar" && !next.activity) next.mode = "dashboard";
    return next;
}

function dismissDashboard(state) {
    var next = clone(state);
    if (!next.pin) next.dashboard = null;
    if (!next.activity && !next.pin && next.mode === "dashboard") next.mode = "idle";
    return next;
}

function pinDashboard(state, route) {
    if (!route || DASHBOARDS.indexOf(route.kind) < 0) return state;
    var next = showDashboard(state, route);
    next.pin = clone(route);
    next.mode = "dashboard";
    return next;
}

function unpinDashboard(state) {
    var next = clone(state);
    next.pin = null;
    next.dashboard = null;
    if (!next.activity) next.mode = "idle";
    return next;
}

function enqueue(state, input, fallbackMonitor) {
    var next = clone(state);
    var activity = normalizeActivity(input, fallbackMonitor);
    next.queue = next.queue.filter(function(item) { return item.id !== activity.id && item.kind !== activity.kind; });
    if (!next.activity || activity.priority >= next.activity.priority) {
        // A visible transient owns its monitor until it retires. A
        // higher-priority replacement may change content, never location.
        if (next.activity && next.targetMonitor) activity.monitor = next.targetMonitor;
        if (next.activity && next.activity.id !== activity.id) next.queue.push(next.activity);
        if (CRITICAL_KINDS.indexOf(activity.kind) >= 0 && next.pin) {
            next.interrupted = { pin: clone(next.pin), dashboard: clone(next.dashboard) };
            next.pin = null;
        }
        next.activity = activity;
        next.targetMonitor = activity.monitor || next.targetMonitor;
        if (next.mode !== "launcher" && next.mode !== "calendar") next.mode = "activity";
    } else {
        next.queue.push(activity);
    }
    next.queue.sort(function(a, b) { return b.priority - a.priority || a.timestamp - b.timestamp; });
    return next;
}

function finishActivity(state, id) {
    var next = clone(state);
    if (next.activity && id && next.activity.id !== id) return next;
    next.activity = null;
    if (next.queue.length > 0) {
        next.activity = next.queue.shift();
        next.targetMonitor = next.activity.monitor || next.targetMonitor;
        if (next.mode !== "launcher" && next.mode !== "calendar") next.mode = "activity";
        return next;
    }
    if (next.interrupted) {
        next.pin = next.interrupted.pin;
        next.dashboard = next.interrupted.dashboard;
        next.interrupted = null;
    }
    if (next.mode !== "launcher" && next.mode !== "calendar") next.mode = next.pin || next.dashboard ? "dashboard" : "idle";
    return next;
}

function escape(state) {
    if (state.mode === "launcher" || state.mode === "calendar") return closeLayer(state);
    if (state.pin) return unpinDashboard(state);
    if (state.dashboard) return dismissDashboard(state);
    return state;
}

function view(state) { return clone(state); }
