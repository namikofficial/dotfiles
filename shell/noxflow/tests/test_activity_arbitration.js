const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

let now = 1000;
const context = { console, Date: { now: () => ++now }, isFinite };
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "ActivityArbitration.js"), "utf8"), context);
const Activity = context;
const route = (kind, monitor = "DP-1") => ({ kind, monitor, targetPanel: "quick-settings", targetSection: kind });
const event = (kind, priority, monitor = "DP-1") => ({ id: kind, kind, priority, title: kind, timeoutMs: 1000, monitor });

(function stableModesAndFocusOwnership() {
    let state = Activity.newState();
    assert.deepStrictEqual(Array.from(Activity.MODES), ["idle", "activity", "dashboard", "launcher", "calendar"]);
    state = Activity.openLayer(state, "launcher", "HDMI-A-1");
    assert.strictEqual(state.focusOwner, "launcher");
    state = Activity.enqueue(state, event("volume", 3), "DP-1");
    assert.strictEqual(state.mode, "launcher", "activity must not steal launcher focus");
    assert.strictEqual(Activity.closeLayer(state).mode, "activity");
})();

(function priorityDedupAndQueueOrder() {
    let state = Activity.enqueue(Activity.newState(), event("volume", 3), "DP-1");
    state = Activity.enqueue(state, event("brightness", 2), "DP-1");
    assert.strictEqual(state.activity.kind, "volume");
    state = Activity.enqueue(state, Object.assign(event("brightness", 4), { id: "brightness-new" }), "DP-1");
    assert.strictEqual(state.activity.id, "brightness-new");
    assert.strictEqual(state.queue.filter(item => item.kind === "brightness").length, 0);
})();

(function explicitPinCriticalRestoreAndRoutineOsd() {
    let state = Activity.pinDashboard(Activity.newState(), route("health"));
    state = Activity.enqueue(state, event("volume", 3), "DP-1");
    assert.strictEqual(state.pin.kind, "health", "routine OSD keeps the pin");
    state = Activity.finishActivity(state, "volume");
    state = Activity.enqueue(state, event("battery-warning", 8), "DP-1");
    assert.strictEqual(state.pin, null, "critical warning temporarily replaces pin");
    state = Activity.finishActivity(state, "battery-warning");
    assert.strictEqual(state.pin.kind, "health", "critical completion restores pin");
})();

(function monitorDoesNotTeleportWhileVisible() {
    let state = Activity.enqueue(Activity.newState(), event("media", 5, "DP-1"), "DP-1");
    state = Activity.enqueue(state, event("brightness", 3, "HDMI-A-1"), "HDMI-A-1");
    assert.strictEqual(state.targetMonitor, "DP-1");
    state = Activity.finishActivity(state, "media");
    assert.strictEqual(state.targetMonitor, "HDMI-A-1");

    state = Activity.enqueue(Activity.newState(), event("volume", 3, "DP-1"), "DP-1");
    state = Activity.enqueue(state, event("battery-warning", 8, "HDMI-A-1"), "HDMI-A-1");
    assert.strictEqual(state.targetMonitor, "DP-1", "priority replacement must stay on the visible monitor");
})();

(function escapeOrder() {
    let state = Activity.pinDashboard(Activity.newState(), route("connectivity"));
    state = Activity.openLayer(state, "calendar", "DP-1");
    state = Activity.escape(state);
    assert.strictEqual(state.mode, "dashboard");
    state = Activity.escape(state);
    assert.strictEqual(state.pin, null);
    state = Activity.escape(state);
    assert.strictEqual(state.mode, "idle");
})();

(function normalizationContract() {
    const normalized = Activity.normalizeActivity({ kind: "build-result", title: "Done", priority: 7 }, "eDP-1");
    for (const key of ["id", "kind", "severity", "priority", "title", "detail", "value", "maximum", "timeoutMs", "targetPanel", "targetSection", "monitor"])
        assert.ok(Object.prototype.hasOwnProperty.call(normalized, key), "missing normalized field " + key);
})();

console.log("noxflow activity arbitration fixtures passed");
