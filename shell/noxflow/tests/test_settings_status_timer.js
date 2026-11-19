const assert = require("assert");
const fs = require("fs");

// Behavioral simulation of SettingsPanel's status auto-clear state machine.
function createStatusController() {
  let now = 0;
  let interactive = false;
  let lastStatusKind = "";
  let lastStatusMessage = "";
  let lastStatusAt = 0;
  const defaultDurationMs = 4000;

  let timerRunning = false;
  let timerInterval = defaultDurationMs;
  let timerDueAt = 0;

  function stopTimer() {
    timerRunning = false;
    timerDueAt = 0;
  }

  function restartTimer() {
    timerRunning = true;
    timerDueAt = now + timerInterval;
  }

  function scheduleStatusClear() {
    if (lastStatusKind === "" || !interactive) {
      stopTimer();
      return;
    }
    timerInterval = defaultDurationMs;
    restartTimer();
  }

  function reportStatus(kind, message) {
    lastStatusKind = kind;
    lastStatusMessage = message;
    lastStatusAt = now;
    scheduleStatusClear();
  }

  function clearStatus() {
    lastStatusKind = "";
    lastStatusMessage = "";
    stopTimer();
  }

  function setInteractive(value) {
    interactive = !!value;
    if (interactive) {
      if (lastStatusKind !== "") scheduleStatusClear();
    } else {
      stopTimer();
    }
  }

  function onTriggered() {
    timerRunning = false;
    const remaining = defaultDurationMs - (now - lastStatusAt);
    if (remaining > 50) {
      timerInterval = Math.max(50, Math.ceil(remaining));
      restartTimer();
      return;
    }
    timerInterval = defaultDurationMs;
    clearStatus();
  }

  function advanceTo(targetMs) {
    while (timerRunning && timerDueAt <= targetMs) {
      now = timerDueAt;
      onTriggered();
    }
    now = targetMs;
  }

  return {
    setInteractive,
    reportStatus,
    clearStatus,
    advanceTo,
    triggerEarlyAt(ms) {
      now = ms;
      onTriggered();
    },
    state: () => ({
      now,
      lastStatusKind,
      lastStatusMessage,
      timerRunning,
      timerDueAt
    })
  };
}

// Scenario 1: A newer status arrives mid-timer -> timer restarts and clears cleanly at tB + 4000.
{
  const ctrl = createStatusController();
  ctrl.setInteractive(true);
  ctrl.reportStatus("external", "Settings are up to date");
  assert.strictEqual(ctrl.state().timerDueAt, 4000);

  ctrl.advanceTo(2500);
  ctrl.reportStatus("saved", "Profile material-focus saved");
  assert.strictEqual(ctrl.state().timerDueAt, 6500, "second status must push timer deadline to tB + 4000");

  ctrl.advanceTo(4100);
  assert.strictEqual(ctrl.state().lastStatusKind, "saved", "new status stays visible at old deadline");
  assert.strictEqual(ctrl.state().timerRunning, true, "timer must still be running after old deadline");

  ctrl.advanceTo(6500);
  assert.strictEqual(ctrl.state().lastStatusKind, "", "status clears cleanly 4s after second status");
  assert.strictEqual(ctrl.state().timerRunning, false);
}

// Scenario 2: Early jitter trigger reschedules remaining time and still clears.
{
  const ctrl = createStatusController();
  ctrl.setInteractive(true);
  ctrl.reportStatus("saved", "Density compact saved");
  ctrl.triggerEarlyAt(3850);
  assert.strictEqual(ctrl.state().lastStatusKind, "saved");
  assert.strictEqual(ctrl.state().timerRunning, true);
  assert.strictEqual(ctrl.state().timerDueAt, 4000);
  ctrl.advanceTo(4000);
  assert.strictEqual(ctrl.state().lastStatusKind, "");
}

// Scenario 3: Status reported before interactive starts counting once interactive becomes true.
{
  const ctrl = createStatusController();
  ctrl.reportStatus("reconnect", "Daemon connecting");
  assert.strictEqual(ctrl.state().timerRunning, false);
  ctrl.advanceTo(1000);
  ctrl.setInteractive(true);
  assert.strictEqual(ctrl.state().timerRunning, true);
  assert.strictEqual(ctrl.state().timerDueAt, 5000);
  ctrl.advanceTo(5000);
  assert.strictEqual(ctrl.state().lastStatusKind, "");
}

const settingsQml = fs.readFileSync(require.resolve("../surfaces/settings/SettingsPanel.qml"), "utf8");
assert(settingsQml.includes("id: statusAutoClearTimer"), "SettingsPanel must name statusAutoClearTimer");
assert(settingsQml.includes("statusAutoClearTimer.restart()"), "SettingsPanel must restart timer explicitly on new status");
assert(!/running:\s*root\.lastStatusKind\s*!==\s*""/.test(settingsQml),
  "statusAutoClearTimer must not rely on a boolean running binding that misses back-to-back updates");
assert(!settingsQml.includes("ScrollBar.AlwaysOn"), "SettingsPanel must not show an always-on scrollbar");
assert(/id:\s*profileGrid[\s\S]*?Layout\.fillWidth:\s*true[\s\S]*?horizontalAlignment:\s*Text\.AlignLeft/.test(settingsQml),
  "SettingsPanel profile cards must left-align labels cleanly");

console.log("ok - settings status timer and Nox Studio layout fixtures passed");
