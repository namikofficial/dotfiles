const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const context = { console };
vm.createContext(context);
vm.runInContext(
    fs.readFileSync(path.join(__dirname, "..", "HoverEngagement.js"), "utf8"),
    context
);

const Hover = context;

// ── Source hold ──────────────────────────────────────────────────────────
// While a source chip claims hover, the island must stay engaged with that
// kind and never fall back to idle, even across many ticks.
(function testSourceHold() {
    var s = Hover.newState();
    s = Hover.recordSourceHover(s, "health", true);
    for (var i = 0; i < 25; i++) {
        var now = i * 100;
        var token = Hover.armTransit(s, now, 900);
        assert.strictEqual(Hover.tickTransit(s, token, now + 50), false,
            "transit must not elapse while source hover remains true (tick " + i + ")");
        assert.strictEqual(Hover.isAnyHovered(s), true);
        assert.strictEqual(Hover.effectiveKind(s), "health");
    }
    console.log("OK testSourceHold");
})();

// ── Island transit ───────────────────────────────────────────────────────
// The pointer leaves the source and enters the island body. Within the
// grace window the engagement survives; once grace elapses with no hover it
// drops to idle.
(function testIslandTransit() {
    var s = Hover.newState();
    s = Hover.recordSourceHover(s, "connectivity", true);
    // pointer leaves source, enters island. Each transition bumps generation
    // (recordSourceHover on a state change), so the caller arms a fresh
    // token against the current generation.
    s = Hover.recordSourceHover(s, "connectivity", false);
    var token = Hover.armTransit(s, 200, 900);
    s = Hover.recordIslandHover(s, true);
    assert.strictEqual(Hover.tickTransit(s, token, 300), false, "island hover should keep engagement alive");
    assert.strictEqual(Hover.isAnyHovered(s), true);
    // pointer leaves island too
    s = Hover.recordIslandHover(s, false);
    assert.strictEqual(Hover.tickTransit(s, token, 600), false, "still inside grace window");
    assert.strictEqual(Hover.tickTransit(s, token, 1200), true, "grace elapsed");
    // Plain tick without hover does not auto-clear — callers must inspect
    // isAnyHovered() before deciding to release.
    assert.strictEqual(Hover.isAnyHovered(s), false);
    console.log("OK testIslandTransit");
})();

// ── Stale generation callbacks ───────────────────────────────────────────
// A queued callback from a replaced engagement must NOT close the new
// engagement, even if its (older) deadline has already passed.
(function testStaleGenerationCallbacks() {
    var s = Hover.newState();
    s = Hover.recordSourceHover(s, "workspace", true);
    var oldToken = Hover.armTransit(s, 0, 900);

    // Replace engagement (e.g. user moved directly to a different source).
    // Each transition bumps generation, so oldToken is now stale.
    s = Hover.recordSourceHover(s, "workspace", false);
    s = Hover.recordSourceHover(s, "audio-power", true);
    var newToken = Hover.armTransit(s, 200, 900);

    // Stale timer fires long after its own deadline but with the OLD generation
    assert.strictEqual(Hover.tickTransit(s, oldToken, 5000), false,
        "stale callback must not elapse for the current engagement");

    // The current token still controls the current engagement; release the
    // source so the timer is actually pending.
    s = Hover.recordSourceHover(s, "audio-power", false);
    var freshToken = Hover.armTransit(s, 600, 900);
    assert.strictEqual(Hover.tickTransit(s, freshToken, 800), false,
        "fresh token must still defer within its grace window");
    assert.strictEqual(Hover.tickTransit(s, freshToken, 1600), true,
        "fresh token elapses once grace is exceeded AND pointer has left");

    // Bumping the generation (e.g. via pin toggle) invalidates outstanding timers
    s = Hover.recordSourceHover(s, "health", true);
    var pre = s.generation;
    var orphan = Hover.armTransit(s, 0, 900);
    s = Hover.togglePin(s, "health");
    assert.notStrictEqual(s.generation, pre, "togglePin must bump generation");
    s = Hover.recordSourceHover(s, "health", false);
    s = Hover.recordIslandHover(s, false);
    assert.strictEqual(Hover.tickTransit(s, orphan, 99999), false,
        "post-generation-bump orphan must never fire");
    console.log("OK testStaleGenerationCallbacks");
})();

// ── Pin persistence across routine OSD ───────────────────────────────────
// A pinned context must survive volume sliders, brightness nudges, mic mute,
// media playback, file transfers, and notifications.
(function testPinPersistenceAcrossOsd() {
    var s = Hover.newState();
    s = Hover.togglePin(s, "health");

    var routine = ["volume", "brightness", "output-mute", "input-mute",
        "media", "file-transfer", "ai-completion", "build-result", "notification"];
    for (var i = 0; i < routine.length; i++) {
        s = Hover.enterOsd(s, routine[i], 2000);
        assert.strictEqual(s.pin.active, true, "OSD " + routine[i] + " must not destroy pin");
        assert.strictEqual(s.pin.kind, "health");
        assert.strictEqual(s.osd.active, true);
        assert.strictEqual(Hover.effectiveKind(s), "health",
            "pin must dominate OSD for " + routine[i]);
        s = Hover.exitOsd(s);
        assert.strictEqual(s.pin.active, true, "OSD exit must leave pin intact");
    }
    console.log("OK testPinPersistenceAcrossOsd");
})();

// ── Critical interrupt / restore ─────────────────────────────────────────
// A critical engagement temporarily replaces the pin and remembers it. When
// the critical engagement exits, the pin is restored automatically.
(function testCriticalInterruptAndRestore() {
    var s = Hover.newState();
    s = Hover.togglePin(s, "connectivity");
    assert.strictEqual(s.pin.active, true);

    s = Hover.enterCritical(s, "battery-warning");
    assert.strictEqual(s.critical.active, true);
    assert.strictEqual(s.critical.kind, "battery-warning");
    assert.strictEqual(s.pin.active, false, "pin is replaced during critical");
    assert.strictEqual(s.critical.restoredPin.active, true);
    assert.strictEqual(s.critical.restoredPin.kind, "connectivity");
    assert.strictEqual(Hover.effectiveKind(s), "battery-warning",
        "critical dominates while active");

    s = Hover.enterCritical(s, "network-warning");
    assert.strictEqual(s.critical.restoredPin.kind, "connectivity",
        "a nested critical interrupt must preserve the original pin");
    assert.strictEqual(Hover.effectiveKind(s), "network-warning");

    // Routine OSD during a critical does not affect the override either
    s = Hover.enterOsd(s, "volume", 2000);
    assert.strictEqual(Hover.effectiveKind(s), "network-warning");
    s = Hover.exitOsd(s);

    s = Hover.exitCritical(s);
    assert.strictEqual(s.critical.active, false);
    assert.strictEqual(s.pin.active, true, "pin must be restored");
    assert.strictEqual(s.pin.kind, "connectivity");
    assert.strictEqual(Hover.effectiveKind(s), "connectivity");
    console.log("OK testCriticalInterruptAndRestore");
})();

// ── Pin release paths ────────────────────────────────────────────────────
// Pin can be released via togglePin(same), releasePin, click-away, panel
// close, another selected context, and Escape. Here we cover the pure
// transitions; the QML side wires Escape/panel-close/click-away.
(function testPinReleasePaths() {
    // re-click / unpin via togglePin(same)
    var s = Hover.newState();
    s = Hover.togglePin(s, "audio-power");
    assert.strictEqual(s.pin.active, true);
    s = Hover.togglePin(s, "audio-power");
    assert.strictEqual(s.pin.active, false, "re-click on same kind unpins");

    // selecting another context replaces the pin without opening a gap
    s = Hover.togglePin(s, "connectivity");
    assert.strictEqual(s.pin.kind, "connectivity");
    s = Hover.togglePin(s, "health");
    assert.strictEqual(s.pin.kind, "health");
    s = Hover.releasePin(s);
    assert.strictEqual(s.pin.active, false);

    // click-away helper
    var src = [{ x: 0, y: 0, width: 50, height: 30 }];
    var island = { x: 100, y: 0, width: 200, height: 40 };
    assert.strictEqual(Hover.isClickAway(s, src, island, { x: 75, y: 5 }), true,
        "pointer between chip and island counts as click-away");
    assert.strictEqual(Hover.isClickAway(s, src, island, { x: 25, y: 5 }), false,
        "pointer over chip does not count as click-away");
    assert.strictEqual(Hover.isClickAway(s, src, island, { x: 150, y: 5 }), false,
        "pointer over island does not count as click-away");
    console.log("OK testPinReleasePaths");
})();

// ── Hover-driven source selection / switch ───────────────────────────────
// Moving the pointer from one source to another must retarget the island
// without ever losing engagement.
(function testHoverSourceSwitch() {
    var s = Hover.newState();
    s = Hover.recordSourceHover(s, "workspace", true);
    assert.strictEqual(Hover.effectiveKind(s), "workspace");
    s = Hover.recordSourceHover(s, "workspace", false);
    s = Hover.recordSourceHover(s, "health", true);
    assert.strictEqual(Hover.effectiveKind(s), "health",
        "newly hovered source wins over the previously hovered one");
    s = Hover.recordSourceHover(s, "health", false);
    s = Hover.recordSourceHover(s, "connectivity", true);
    assert.strictEqual(Hover.effectiveKind(s), "connectivity");
    s = Hover.clearSourceHover(s);
    assert.strictEqual(Hover.isAnySourceHovered(s), false);
    console.log("OK testHoverSourceSwitch");
})();

// ── Diagnostics view ─────────────────────────────────────────────────────
// view() must produce a serializable, immutable snapshot suitable for logs.
(function testDiagnosticsView() {
    var s = Hover.newState();
    s = Hover.recordSourceHover(s, "health", true);
    s = Hover.togglePin(s, "health");
    var v = Hover.view(s);
    assert.strictEqual(v.pin.kind, "health");
    assert.strictEqual(v.effective, "health");
    assert.strictEqual(v.engaged, true);
    // mutating the view must not mutate the underlying state
    v.pin.kind = "tampered";
    assert.strictEqual(s.pin.kind, "health");
    console.log("OK testDiagnosticsView");
})();

console.log("noxflow hover engagement fixtures passed");
