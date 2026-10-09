// test_surface_stack.js — regression coverage for the modal stack and Escape.
//
// Why this test exists: the shell had two coordinators that could not see each
// other. PanelController closed every other panel when one opened, while
// SurfaceCoordinator — the only thing Escape consulted — documented the
// opposite rule ("panels may coexist with each other and with modals"). Neither
// was wrong on its own terms; together they meant "one panel at a time" and
// "any number of panels" were both true depending on who you asked.
//
// Escape in particular could not be verified by hand here: no key-injection
// tool is installed and Hyprland's lua dispatch rejects sendshortcap, so the
// routing is pinned down as a unit test against the module the controller
// actually calls.

const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const context = {};
vm.createContext(context);
vm.runInContext(
  fs.readFileSync(require.resolve("../core/SurfaceStack.js"), "utf8").replace(/^\.pragma.*$/gm, ""),
  context);
const { push, remove, topmost, escapeTarget } = context;

const alive = () => false;

// ── Stacking ──
{
  const dashboard = { name: "dashboard" };
  const launcher = { name: "launcher" };
  let stack = push([], dashboard);
  stack = push(stack, launcher);
  assert.strictEqual(stack.length, 2, "both modals are tracked");
  assert.strictEqual(topmost(stack, alive), launcher,
    "the most recently opened modal is on top");
}

// Re-registering must not duplicate: a surface can re-run Component.onCompleted
// after a config reload, and a doubled entry would make Escape close the same
// modal twice.
{
  const s = { name: "settings" };
  let stack = push(push([], s), s);
  assert.strictEqual(stack.length, 1, "re-registering the same modal is idempotent");
  stack = push(push([], s), { name: "other" });
  assert.strictEqual(stack.length, 2, "a different modal is still added");
}

// ── Removal ──
{
  const a = { name: "a" };
  const b = { name: "b" };
  const stack = push(push([], a), b);
  assert.strictEqual(remove(stack, a).length, 1, "removal drops exactly one entry");
  assert.strictEqual(topmost(remove(stack, a), alive), b);
  assert.deepStrictEqual(remove(stack, { name: "absent" }), stack,
    "removing an absent surface leaves the stack identical");
  assert.deepStrictEqual(remove(stack, null), stack,
    "removing null is a no-op rather than emptying the stack");
}

// ── A destroyed entry must not swallow the key ──
//
// Accessing a method on a deleted QML object throws. topmost() has to skip
// dead entries rather than return them.
{
  const dead = { name: "dead", destroyed: true };
  const live = { name: "live" };
  const isDead = (s) => s === dead;
  let stack = push([], live);
  stack = push(stack, dead);
  assert.strictEqual(topmost(stack, isDead), live,
    "a destroyed modal is skipped, not returned");
  assert.strictEqual(escapeTarget(stack, "notifications", isDead).surface, live,
    "Escape must target the surviving modal");
}

// ── Escape routing ──
// A modal always wins: it is the thing on top of the screen.
{
  const stack = push([], { name: "launcher" });
  const target = escapeTarget(stack, "notifications", alive);
  assert.strictEqual(target.type, "modal");
  assert.strictEqual(target.surface.name, "launcher");
}

// With no modal, Escape falls through to the active panel.
{
  const target = escapeTarget([], "calendar", alive);
  assert.strictEqual(target.type, "panel");
  assert.strictEqual(target.surface, "calendar");
}

// With nothing open at all it reports none, so the caller can let the key
// propagate instead of swallowing it.
{
  const target = escapeTarget([], "", alive);
  assert.strictEqual(target.type, "none");
  assert.strictEqual(target.surface, null);
}

// Every modal destroyed, panel still open: the panel must remain reachable,
// otherwise a crashed overlay would permanently lock the user out of Escape.
{
  const dead = { name: "dead", destroyed: true };
  const stack = push([], dead);
  const target = escapeTarget(stack, "notifications", (s) => s === dead);
  assert.strictEqual(target.type, "panel");
  assert.strictEqual(target.surface, "notifications");
}

// Stacked modals close one at a time, from the top down — the second Escape
// after two modals must not close the same one again.
{
  let stack = push([], { name: "dashboard" });
  stack = push(stack, { name: "capture" });
  const first = escapeTarget(stack, "", alive);
  assert.strictEqual(first.surface.name, "capture");
  stack = remove(stack, first.surface);
  const second = escapeTarget(stack, "", alive);
  assert.strictEqual(second.surface.name, "dashboard",
    "after dismissing the top modal, Escape reaches the one beneath it");
  stack = remove(stack, second.surface);
  assert.strictEqual(escapeTarget(stack, "", alive).type, "none",
    "Escape reports nothing left to close once the stack empties");
}

console.log("ok - surface stack and escape routing");