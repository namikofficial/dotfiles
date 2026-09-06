const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

// NF-05 contract test: SettingsPanel must hydrate from the canonical daemon
// API (get_settings) and reconcile preview / pending / saved / rejected /
// external-update / reconnect states. We exercise the pure JS portions of
// the panel logic (result unwrapping, state machine transitions) without a
// full Quickshell runtime, the same way test_protocol.js does it.

// ── Canonical response shape (mirrors core/noxflow-ipc/src/lib.rs) ──
// Response::Settings(SettingsMap { settings }) is tagged `type: "settings"`
// with `data: { settings: {...} }`. SettingUpdated echoes `type:
// "setting_updated"` with `data: { key, value }`. The QML layer never
// receives the bare SettingsMap — it always arrives wrapped in the response
// envelope's `result` field.
function makeGetSettingsResponse(map) {
  return {
    type: "settings",
    data: { settings: map }
  };
}
function makeSettingUpdatedResponse(key, value) {
  return {
    type: "setting_updated",
    data: { key: key, value: value }
  };
}
function makeErrorResponse(code, message) {
  return { code: code, message: message };
}

// Mirror of SettingsPanel.qml's applyAppearanceFromMap logic. The real panel
// drives Tokens via Theme.Tokens.* bindings; here we record what would have
// been written to keep the assertion surface deterministic.
function makePanelStub() {
  const state = {
    profile: "material-expressive",
    density: "comfortable",
    motion: false,
    radius: 14,
    pendingWrites: {},
    previousValues: {},
    status: { kind: "", key: "", message: "", at: 0 }
  };
  function capturePrevious(key) {
    switch (key) {
      case "appearance.profile": return state.profile;
      case "appearance.density": return state.density;
      case "shell.reduced_motion": return state.motion;
      case "appearance.radius": return state.radius;
      default: return undefined;
    }
  }
  function applyLocal(key, value) {
    switch (key) {
      case "appearance.profile": state.profile = String(value); break;
      case "appearance.density": state.density = String(value); break;
      case "shell.reduced_motion": state.motion = !!value; break;
      case "appearance.radius":
        state.radius = Math.max(0, Math.min(36, Math.round(Number(value) || 0)));
        break;
    }
  }
  function writeSetting(noxd, key, value, label) {
    if (!noxd || !noxd.connected) {
      state.status = { kind: "reconnect", key: key, message: label + ": waiting", at: Date.now() };
      return;
    }
    state.previousValues[key] = capturePrevious(key);
    state.pendingWrites[key] = { value: value, label: label };
    state.status = { kind: "pending", key: key, message: label, at: Date.now() };
    applyLocal(key, value);
    noxd.settingSink(key, value, function(ack) {
      if (ack && ack.key === key) {
        delete state.pendingWrites[key];
        state.status = { kind: "saved", key: key, message: label + " saved", at: Date.now() };
      }
    }, function(code, message) {
      // Reject path: revert to previous good value.
      const prior = state.previousValues[key];
      if (prior !== undefined) applyLocal(key, prior);
      delete state.pendingWrites[key];
      state.status = { kind: "rejected", key: key, message: label + ": " + (message || code), at: Date.now() };
    });
  }
  function hydrate(noxd) {
    if (!noxd || !noxd.connected) {
      state.status = { kind: "reconnect", key: "", message: "daemon unavailable", at: Date.now() };
      return { hydrationLoaded: false };
    }
    noxd.settingsSink(function(result) {
      const map = result && result.data && result.data.settings;
      if (map) {
        if (map["appearance.profile"] !== undefined) state.profile = String(map["appearance.profile"]);
        if (map["appearance.density"] !== undefined) state.density = String(map["appearance.density"]);
        if (map["shell.reduced_motion"] !== undefined) state.motion = !!map["shell.reduced_motion"];
        if (map["appearance.radius"] !== undefined) {
          state.radius = Math.max(0, Math.min(36, Math.round(Number(map["appearance.radius"]) || 0)));
        }
        state.status = { kind: "external", key: "", message: "settings hydrated", at: Date.now() };
      }
    });
    return { hydrationLoaded: true };
  }
  return { state: state, writeSetting: writeSetting, hydrate: hydrate };
}

function makeFakeNoxd(opts) {
  const noxd = {
    connected: opts.connected !== false,
    settingSink: function(key, value, cb, ecb) {
      this._pending = this._pending || [];
      this._pending.push({ key: key, value: value, cb: cb, ecb: ecb });
    },
    settingsSink: function(cb) { this._settingsCb = cb; }
  };
  return noxd;
}

// ── Test: hydration from get_settings applies the canonical map ──
(function testHydrationAppliesCanonicalValues() {
  const noxd = makeFakeNoxd({ connected: true });
  const panel = makePanelStub();
  panel.hydrate(noxd);
  // Simulate the daemon's settings map arriving in the response wrapper.
  noxd._settingsCb(makeGetSettingsResponse({
    "appearance.profile": "material-oled",
    "appearance.density": "compact",
    "shell.reduced_motion": true,
    "appearance.radius": 20
  }));
  assert.strictEqual(panel.state.profile, "material-oled", "profile must hydrate");
  assert.strictEqual(panel.state.density, "compact", "density must hydrate");
  assert.strictEqual(panel.state.motion, true, "motion must hydrate");
  assert.strictEqual(panel.state.radius, 20, "radius must hydrate");
  assert.strictEqual(panel.state.status.kind, "external", "external-update status recorded");
  console.log("OK testHydrationAppliesCanonicalValues");
})();

// ── Test: write -> pending -> saved flow ──
(function testWritePendingThenSaved() {
  const noxd = makeFakeNoxd({ connected: true });
  const panel = makePanelStub();
  panel.state.previousValues["appearance.profile"] = panel.state.profile;
  panel.writeSetting(noxd, "appearance.profile", "material-focus", "Profile material-focus");
  assert.strictEqual(panel.state.profile, "material-focus", "preview applies immediately");
  assert.strictEqual(panel.state.pendingWrites["appearance.profile"].value, "material-focus",
    "pending tracking includes the new value");
  // Daemon confirms via SettingUpdated envelope.
  noxd._pending[0].cb(makeSettingUpdatedResponse("appearance.profile", "material-focus").data);
  assert.strictEqual(panel.state.pendingWrites["appearance.profile"], undefined,
    "accepted writes are removed from pending");
  assert.strictEqual(panel.state.status.kind, "saved", "saved status recorded");
  assert.strictEqual(panel.state.status.key, "appearance.profile");
  console.log("OK testWritePendingThenSaved");
})();

// ── Test: write -> pending -> rejected reverts to previous value ──
(function testWritePendingThenRejectedReverts() {
  const noxd = makeFakeNoxd({ connected: true });
  const panel = makePanelStub();
  panel.state.previousValues["appearance.radius"] = 14;
  panel.writeSetting(noxd, "appearance.radius", 99, "Radius 99px");
  assert.strictEqual(panel.state.radius, 36, "preview clamps to max (36)");
  assert.strictEqual(panel.state.pendingWrites["appearance.radius"].value, 99,
    "pending tracking includes the attempted value");
  noxd._pending[0].ecb("invalid_params", "radius must be an integer between 0 and 36");
  assert.strictEqual(panel.state.radius, 14, "rejection reverts radius to previous value");
  assert.strictEqual(panel.state.pendingWrites["appearance.radius"], undefined,
    "rejected writes are removed from pending");
  assert.strictEqual(panel.state.status.kind, "rejected", "rejected status recorded");
  assert.ok(panel.state.status.message.indexOf("radius") >= 0,
    "rejected message surfaces daemon error: " + panel.state.status.message);
  console.log("OK testWritePendingThenRejectedReverts");
})();

// ── Test: reconnect surfaces a reconnect status and skips the write ──
(function testDisconnectedSkipsWrite() {
  const noxd = makeFakeNoxd({ connected: false });
  const panel = makePanelStub();
  panel.state.previousValues["appearance.density"] = "comfortable";
  panel.writeSetting(noxd, "appearance.density", "spacious", "Density spacious");
  assert.strictEqual(panel.state.status.kind, "reconnect",
    "writes while disconnected report reconnect");
  assert.strictEqual(noxd._pending, undefined,
    "no IPC request is dispatched while disconnected");
  console.log("OK testDisconnectedSkipsWrite");
})();

// ── Test: SettingsPanel must NOT claim reload is supported when the service
// has no ExecReload. Source-of-truth check: the panel wires Process-based
// maintenance commands rather than silent Quickshell.exec reload calls.
(function testMaintenanceUsesProcessAndRestart() {
  const settings = fs.readFileSync(
    require.resolve("../surfaces/settings/SettingsPanel.qml"), "utf8");
  assert.ok(settings.indexOf("Quickshell.exec(\"systemctl --user reload noxflow-shell\")") < 0,
    "SettingsPanel must not silently reload the shell (CanReload=no)");
  assert.ok(/"systemctl".*"--user".*"restart".*"noxflow-shell"/.test(settings),
    "SettingsPanel must use the verified restart operation for shell maintenance");
  assert.ok(settings.indexOf("maintenanceProc") >= 0 && settings.indexOf("onExited") >= 0,
    "Maintenance commands must capture exit codes via Process.onExited");
  assert.ok(settings.indexOf("systemctl --user start noxflow-gallery") < 0,
    "SettingsPanel must not reference the non-existent noxflow-gallery unit");
  console.log("OK testMaintenanceUsesProcessAndRestart");
})();

// ── Test: PanelController must define unregisterPanel so per-monitor
// MorphSurface destruction cannot leak stale references into the controller.
(function testPanelControllerDefinesUnregisterAfterDestruction() {
  const controller = fs.readFileSync(
    require.resolve("../core/PanelController.qml"), "utf8");
  const shell = fs.readFileSync(
    require.resolve("../shell.qml"), "utf8");
  assert.ok(/function unregisterPanel\(/.test(controller),
    "PanelController.qml must define an unregisterPanel function");
  assert.ok(/function pruneDestroyed\(/.test(controller),
    "PanelController.qml must define a pruneDestroyed guard");
  assert.ok(/function isDestroyed\(/.test(controller),
    "PanelController.qml must define an isDestroyed probe");
  assert.ok(/Component\.onDestruction:[\s\S]*?panelController\.unregisterPanel\("quick-settings", this\)/.test(shell),
    "shell.qml must unregister quick-settings on per-monitor destruction");
  assert.ok(/Component\.onDestruction:[\s\S]*?panelController\.unregisterPanel\("calendar", this\)/.test(shell),
    "shell.qml must unregister calendar on per-monitor destruction");
  // NF-03: open must be idempotent — when activePanel === name it must
  // return true without calling close(name).
  assert.ok(/function open\(name/.test(controller),
    "PanelController.qml must define open()");
  const idempotencyBranch = /if \(activePanel === name && surface\(name\) === target\)\s*\{[\s\S]*?return true;/.exec(controller);
  assert.ok(idempotencyBranch, "open() must have an idempotent branch that returns true");
  assert.ok(!/close\(name\)/.test(idempotencyBranch[0]),
    "open() must NOT call close(name) when activePanel === name (NF-03 idempotency)");
  // NF-03: toggle must be distinct from open. The original bug was a one-line
  // alias `function toggle(name, ...) { return open(name, ...); }`. A correct
  // implementation must branch on activePanel === name and call close in that
  // branch.
  const toggleFn = /function toggle\(name[^{]*\{[\s\S]*?\n    \}/.exec(controller);
  assert.ok(toggleFn, "PanelController.qml must define toggle() with a real body");
  const toggleBody = toggleFn[0];
  // Reject the bare-alias shape: single-line body that just forwards to open.
  assert.ok(!/function toggle\(name[\s\S]*?\{ return open\(/.test(controller),
    "toggle must not be a bare alias of open (NF-03 toggle distinction)");
  assert.ok(/close\(name\)/.test(toggleBody),
    "toggle(name) must call close(name) when activePanel === name");
  // NF-03: close must be name-safe — must NOT clear activePanel when closing
  // a different name.
  const closeFn = /function close\(name[^{]*\{[\s\S]*?\n    \}/.exec(controller);
  assert.ok(closeFn, "PanelController.qml must define close() with a real body");
  assert.ok(/requested !== activePanel/.test(closeFn[0]),
    "close(name) must compare requested against activePanel and leave it alone on mismatch (NF-03 name-safety)");
  console.log("OK testPanelControllerDefinesUnregisterAfterDestruction");
})();

// ── Test: Tokens.applyRadius must keep appearanceRadius in sync ──
(function testApplyRadiusKeepsAppearanceRadiusInSync() {
  const tokens = fs.readFileSync(
    require.resolve("../theme/Tokens.qml"), "utf8");
  // appearanceRadius must be writable (not readonly).
  const radiusDecl = tokens.match(/property\s+int\s+appearanceRadius\s*:\s*\d+/);
  assert.ok(radiusDecl, "Tokens.qml must declare appearanceRadius as a writable property (no readonly)");
  assert.ok(/function applyRadius\([^)]*\)\s*\{[\s\S]*?appearanceRadius\s*=\s*clamped/.test(tokens),
    "Tokens.applyRadius must update appearanceRadius so the radius label reflects the effective state");
  console.log("OK testApplyRadiusKeepsAppearanceRadiusInSync");
})();

// ── Test: SettingsPanel must call noxd.getSettings to hydrate ──
(function testSettingsPanelHydratesFromDaemon() {
  const settings = fs.readFileSync(
    require.resolve("../surfaces/settings/SettingsPanel.qml"), "utf8");
  assert.ok(/noxd\.getSettings\(/.test(settings),
    "SettingsPanel must hydrate from noxd.getSettings");
  assert.ok(/applyAppearanceFromMap\(/.test(settings),
    "SettingsPanel must apply the hydrated map to local tokens");
  assert.ok(/writeSetting\(/.test(settings),
    "SettingsPanel must route writes through a tracked path with callbacks");
  assert.ok(/pendingWrites/.test(settings),
    "SettingsPanel must track per-key pending writes for the pending UI state");
  console.log("OK testSettingsPanelHydratesFromDaemon");
})();

// ── Test: NoxdClient.setSetting must accept callbacks (NF-05 plumbing) ──
(function testNoxdClientSetSettingAcceptsCallbacks() {
  const client = fs.readFileSync(
    require.resolve("../NoxdClient.qml"), "utf8");
  const fn = client.match(/function setSetting\([^)]*\)/);
  assert.ok(fn, "NoxdClient.setSetting must exist");
  assert.ok(/callback|errorCallback/.test(fn[0]),
    "NoxdClient.setSetting must accept callback + errorCallback parameters for the saved/rejected flow");
  console.log("OK testNoxdClientSetSettingAcceptsCallbacks");
})();

console.log("noxflow panel lifecycle / settings hydration contract fixtures passed");
