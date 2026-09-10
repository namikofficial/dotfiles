// Behavioral unit tests for the panel lifecycle state machine.
//
// The QML implementation lives in shell/noxflow/core/PanelController.qml and
// uses Quickshell-specific objects (Screen, Component). To exercise the
// state-transition logic without spinning up a windowing system, this
// module re-implements the same control-flow in plain JavaScript and runs
// it against mock surfaces. The mock mirrors the same external
// observable contract (activePanel, open/close/toggle, unregisterPanel,
// surfaceClosed) that the QML implementation must honor, so any
// algorithmic divergence between this file and PanelController.qml is a
// regression to fix in the QML, not in the test.

const assert = require("assert");

function createMockSurface(name, screenName) {
  return {
    name: name,
    screen: screenName ? { name: screenName } : null,
    openPanelCalls: [],
    closePanelCalls: [],
    destroyed: false,
    openPanel: function(panelName, rect, section) {
      this.openPanelCalls.push({ panelName: panelName, rect: rect, section: section });
    },
    closePanel: function() {
      this.closePanelCalls.push({ when: Date.now() });
    }
  };
}

function createController() {
  function isDestroyed(inst) {
    if (!inst) return true;
    if (inst.destroyed) return true;
    try { var probe = inst.screen; return probe === undefined; } catch (e) { return true; }
  }
  var state = {
    activePanel: "",
    previousPanel: "",
    targetMonitor: "",
    originRect: { x: 0, y: 0, width: 0, height: 0 },
    isInteractive: false,
    isAnimating: false,
    panels: {},
    state: 0, // Hidden
    triggerRegistry: null
  };
  function panelChanged(name, previous) {
    state.lastChange = { name: name, previous: previous };
  }
  function registerPanel(name, surface) {
    var list = (state.panels[name] || []).slice();
    if (list.indexOf(surface) < 0) list.push(surface);
    state.panels[name] = list;
  }
  function unregisterPanel(name, surface) {
    var list = state.panels[name];
    if (!list) return false;
    var idx = list.indexOf(surface);
    if (idx < 0) return false;
    var nextList = list.slice();
    nextList.splice(idx, 1);
    if (nextList.length === 0) delete state.panels[name];
    else state.panels[name] = nextList;
    if (state.activePanel === name) {
      state.previousPanel = name;
      state.activePanel = "";
      panelChanged("", name);
    }
    return true;
  }
  function pruneDestroyed() {
    var changed = false;
    var next = {};
    for (var key in state.panels) {
      var list = state.panels[key];
      var kept = [];
      for (var i = 0; i < list.length; i++) {
        if (isDestroyed(list[i])) { changed = true; continue; }
        kept.push(list[i]);
      }
      if (kept.length > 0) next[key] = kept;
      else if (list.length > 0) changed = true;
    }
    if (changed) state.panels = next;
    return changed;
  }
  function surface(name) {
    var list = state.panels[name] || [];
    for (var i = 0; i < list.length; i++) {
      var inst = list[i];
      if (isDestroyed(inst)) continue;
      if (state.targetMonitor && inst.screen && inst.screen.name === state.targetMonitor) return inst;
      return inst; // single mock instance
    }
    return null;
  }
  function closeSurface(name) {
    var list = state.panels[name] || [];
    for (var i = 0; i < list.length; i++) {
      var inst = list[i];
      if (isDestroyed(inst)) continue;
      if (typeof inst.closePanel === "function") inst.closePanel();
    }
  }
  function open(name) {
    state.targetMonitor = "primary";
    pruneDestroyed();
    var list = state.panels[name];
    if (!list || list.length === 0) return false;
    var target = surface(name);
    if (!target) return false;
    if (state.activePanel === name && surface(name) === target) {
      // Idempotent stay-open. No openPanel call (no section retarget).
      return true;
    }
    var old = state.activePanel;
    state.previousPanel = old;
    // Close every other panel's surfaces (mirrors the QML `for key in panels`
    // closeSurface loop). Only mutates active state if THIS panel becomes
    // active further down — closeSurface() only invokes closePanel on the
    // surfaces, not the controller state.
    for (var key in state.panels) {
      if (key !== name) closeSurface(key);
    }
    state.activePanel = name;
    if (typeof target.openPanel === "function") target.openPanel(name, state.originRect, "");
    state.isInteractive = true;
    panelChanged(name, old);
    return true;
  }
  function toggle(name) {
    if (state.activePanel === name && surface(name)) return close(name);
    return open(name);
  }
  function close(name) {
    var requested = name || state.activePanel;
    if (!requested) return false;
    if (requested !== state.activePanel) {
      closeSurface(requested);
      return true;
    }
    closeSurface(requested);
    state.previousPanel = requested;
    state.activePanel = "";
    state.isInteractive = false;
    panelChanged("", requested);
    return true;
  }
  function surfaceClosed(name, instance) {
    if (state.activePanel !== name) return;
    if (instance && isDestroyed(instance)) return;
    if (instance) {
      var current = surface(name);
      if (current && current !== instance) return;
    }
    state.previousPanel = name;
    state.activePanel = "";
    state.isInteractive = false;
    panelChanged("", name);
  }
  return {
    state: state,
    registerPanel: registerPanel,
    unregisterPanel: unregisterPanel,
    surface: surface,
    open: open,
    close: close,
    toggle: toggle,
    surfaceClosed: surfaceClosed,
    pruneDestroyed: pruneDestroyed
  };
}

// ── Test: open(A), open(A) stays open (NF-03 idempotency) ──
(function testOpenIsIdempotent() {
  var c = createController();
  var a = createMockSurface("a", "primary");
  c.registerPanel("A", a);
  assert.strictEqual(c.open("A"), true, "first open(A) succeeds");
  assert.strictEqual(c.state.activePanel, "A", "activePanel is A");
  assert.strictEqual(a.openPanelCalls.length, 1, "first open triggers openPanel");
  assert.strictEqual(c.open("A"), true, "second open(A) is idempotent (returns true)");
  assert.strictEqual(a.openPanelCalls.length, 1, "second open does NOT trigger openPanel");
  assert.strictEqual(a.closePanelCalls.length, 0, "second open does NOT close A");
  assert.strictEqual(c.state.activePanel, "A", "activePanel stays A after second open");
  console.log("OK testOpenIsIdempotent");
})();

// ── Test: close(B) while A is active leaves A active (NF-03 name-safety) ──
//
// `open(A)` closes B's surface once (the implementation closes every other
// panel on switch). After that, `close(B)` while A is active must NOT touch
// A — it only re-issues closePanel on B's already-closed surface and leaves
// activePanel alone.
(function testCloseOfDifferentNameLeavesActiveAlone() {
  var c = createController();
  var a = createMockSurface("a", "primary");
  var b = createMockSurface("b", "primary");
  c.registerPanel("A", a);
  c.registerPanel("B", b);
  assert.strictEqual(c.open("A"), true);
  assert.strictEqual(c.state.activePanel, "A");
  var aCloseBefore = a.closePanelCalls.length;
  var bCloseBefore = b.closePanelCalls.length;
  assert.strictEqual(c.close("B"), true, "close(B) returns true");
  assert.strictEqual(a.closePanelCalls.length, aCloseBefore,
    "A's surface was NOT closed by close(B) — A must remain visible");
  assert.strictEqual(b.closePanelCalls.length, bCloseBefore + 1,
    "B's surface received an additional closePanel call");
  assert.strictEqual(c.state.activePanel, "A",
    "A remains the only active panel after close(B)");
  console.log("OK testCloseOfDifferentNameLeavesActiveAlone");
})();

// ── Test: toggle(A) closes A (NF-03 toggle distinction) ──
(function testToggleClosesActivePanel() {
  var c = createController();
  var a = createMockSurface("a", "primary");
  c.registerPanel("A", a);
  assert.strictEqual(c.toggle("A"), true, "first toggle(A) opens A");
  assert.strictEqual(c.state.activePanel, "A");
  assert.strictEqual(a.openPanelCalls.length, 1);
  assert.strictEqual(c.toggle("A"), true, "second toggle(A) closes A");
  assert.strictEqual(c.state.activePanel, "", "activePanel cleared after second toggle");
  assert.strictEqual(a.closePanelCalls.length, 1, "A's surface received closePanel");
  console.log("OK testToggleClosesActivePanel");
})();

// ── Test: switching from A to B produces exactly one active panel ──
(function testSwitchFromAToBProducesOneActivePanel() {
  var c = createController();
  var a = createMockSurface("a", "primary");
  var b = createMockSurface("b", "primary");
  c.registerPanel("A", a);
  c.registerPanel("B", b);
  c.open("A");
  assert.strictEqual(c.state.activePanel, "A");
  c.open("B");
  assert.strictEqual(c.state.activePanel, "B", "B is now active");
  assert.strictEqual(a.closePanelCalls.length, 1, "A was closed when switching to B");
  assert.strictEqual(b.openPanelCalls.length, 1, "B received openPanel");
  assert.strictEqual(c.state.activePanel === "A" && c.state.activePanel === "B" ? "ambiguous" : c.state.activePanel, "B",
    "exactly one panel is active");
  console.log("OK testSwitchFromAToBProducesOneActivePanel");
})();

// ── Test: unregisterPanel for the active surface transitions to Hidden ──
(function testUnregisterPanelOfActiveSurfaceClearsActive() {
  var c = createController();
  var a = createMockSurface("a", "primary");
  c.registerPanel("A", a);
  c.open("A");
  assert.strictEqual(c.state.activePanel, "A");
  c.unregisterPanel("A", a);
  assert.strictEqual(c.state.activePanel, "", "activePanel cleared on unregister of active surface");
  assert.strictEqual(c.state.panels["A"], undefined, "panel name removed when list is empty");
  console.log("OK testUnregisterPanelOfActiveSurfaceClearsActive");
})();

// ── Test: destroyed surfaces cannot be selected ──
(function testDestroyedSurfacesCannotBeSelected() {
  var c = createController();
  var a = createMockSurface("a", "primary");
  c.registerPanel("A", a);
  a.destroyed = true;
  assert.strictEqual(c.surface("A"), null, "surface() returns null for a destroyed entry");
  assert.strictEqual(c.open("A"), false, "open() refuses to open a destroyed surface");
  console.log("OK testDestroyedSurfacesCannotBeSelected");
})();

// ── Test: registerPanel is idempotent (no duplicate entry) ──
(function testRegisterPanelIsIdempotent() {
  var c = createController();
  var a = createMockSurface("a", "primary");
  c.registerPanel("A", a);
  c.registerPanel("A", a);
  assert.strictEqual(c.state.panels["A"].length, 1, "duplicate registration is a no-op");
  console.log("OK testRegisterPanelIsIdempotent");
})();

// ── Test: surfaceClosed does not clear active state for a different instance ──
(function testSurfaceClosedForStaleInstanceIsIgnored() {
  var c = createController();
  var a1 = createMockSurface("a1", "primary");
  c.registerPanel("A", a1);
  c.open("A");
  // A second instance (different monitor) sends surfaceClosed — controller
  // must keep active state aligned with the still-live instance.
  var a2 = createMockSurface("a2", "primary");
  c.registerPanel("A", a2);
  c.surfaceClosed("A", a2);
  assert.strictEqual(c.state.activePanel, "A",
    "activePanel stays A when a stale instance reports closed");
  console.log("OK testSurfaceClosedForStaleInstanceIsIgnored");
})();

// ── Test: surfaceClosed for the live instance clears active state ──
(function testSurfaceClosedForLiveInstanceClearsActive() {
  var c = createController();
  var a = createMockSurface("a", "primary");
  c.registerPanel("A", a);
  c.open("A");
  c.surfaceClosed("A", a);
  assert.strictEqual(c.state.activePanel, "", "activePanel cleared by surfaceClosed");
  console.log("OK testSurfaceClosedForLiveInstanceClearsActive");
})();

console.log("noxflow panel lifecycle behavioral fixtures passed");
