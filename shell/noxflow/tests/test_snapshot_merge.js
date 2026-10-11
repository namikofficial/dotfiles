// test_snapshot_merge.js — regression coverage for how a provider snapshot
// combines with the cached one.
//
// Why this test exists: NoxdClient merged a *subscription* snapshot into the
// previous provider state instead of replacing it. Every key the provider had
// dropped was resurrected from the cache and stayed in the UI forever — a
// disconnected SSID came back, a list a provider had emptied stayed populated.
// Nothing errored and no status disagreed, because the models were handed data
// that was simply no longer true.
//
// The same code path also invented health: an event envelope carries no status
// field, and the client asserted `status: "available"` for one, flipping a
// provider the daemon had marked error back to green on every event it emitted.

const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const context = { Math, JSON };
vm.createContext(context);
vm.runInContext(
  fs.readFileSync(require.resolve("../SnapshotMerge.js"), "utf8").replace(/^\.pragma.*$/gm, ""),
  context);
const { isFullSnapshot, mergeEventData, apply, statusAfterEvent } = context;

// ── A complete snapshot replaces, and that is the whole regression ──
//
// The provider used to report two networks and now reports one. Merging would
// keep the departed one alive indefinitely.
{
  const previous = {
    provider: "network",
    status: "available",
    data: { available_wifi: ["HomeNet", "GuestNet"], active: "HomeNet" }
  };
  const snapshot = {
    provider: "network",
    status: "available",
    data: { available_wifi: ["HomeNet"], active: "HomeNet" }
  };

  const replaced = apply(previous, snapshot, true);
  assert.deepStrictEqual(
    Object.keys(replaced.data).sort(), ["active", "available_wifi"],
    "a complete snapshot must not inherit keys from the cache");
  assert.deepStrictEqual(replaced.data.available_wifi, ["HomeNet"],
    "the departed network must not survive a complete snapshot");
}

// A provider that empties a list must actually be seen to empty it.
{
  const previous = { provider: "bluetooth", status: "available", data: { devices: ["a", "b"] } };
  const snapshot = { provider: "bluetooth", status: "available", data: { devices: [] } };
  const replaced = apply(previous, snapshot, true);
  assert.deepStrictEqual(replaced.data.devices, [],
    "an emptied list must read as empty, not as the cached contents");
}

// ── A partial event still merges ──
//
// An event says something about one provider, not everything about it, so
// untouched keys have to survive.
{
  const previous = { provider: "audio", status: "available", data: { volume: 40, muted: false, sink: "headset" } };
  const event = { provider: "audio", status: "available", data: { volume: 55 } };
  const merged = apply(previous, event, false);
  assert.strictEqual(merged.data.volume, 55, "the event must win");
  assert.strictEqual(merged.data.muted, false, "untouched keys must be carried over");
  assert.strictEqual(merged.data.sink, "headset", "untouched keys must be carried over");
}

// An event must not fold into a provider that has already failed: that would
// hide the failure behind plausible stale data.
{
  const failed = { provider: "network", status: "error", data: { available_wifi: [] } };
  const event = { provider: "network", status: "available", data: { available_wifi: ["HomeNet"] } };
  const merged = apply(failed, event, false);
  assert.strictEqual(merged.status, "available");
  assert.deepStrictEqual(merged.data.available_wifi, ["HomeNet"]);
  // With nothing cached, or no previous entry, there is nothing to merge into.
  const noPrevious = apply(undefined, event, false);
  assert.deepStrictEqual(noPrevious.data.available_wifi, ["HomeNet"]);
}

// ── An event must not assert health ──
//
// This is the other half of the bug: an EventEnvelope has no status field, so
// the client must not conclude the provider is fine.
{
  const failed = { provider: "network", status: "error", data: {} };
  assert.strictEqual(statusAfterEvent(failed), "error",
    "an event must not flip an errored provider back to available");

  const unavailable = { provider: "media", status: "unavailable", data: {} };
  assert.strictEqual(statusAfterEvent(unavailable), "unavailable");

  // A provider we have never heard of counts as available: receiving data from
  // it is the evidence.
  assert.strictEqual(statusAfterEvent(undefined), "available");
  assert.strictEqual(statusAfterEvent({ data: {} }), "available");
  // An entry with a falsy status carries no information; fall back.
  assert.strictEqual(statusAfterEvent({ status: "" }), "available");
}

// ── Guards on the input shape ──
{
  assert.strictEqual(isFullSnapshot({ provider: "p", status: "available", data: {} }), true);
  assert.strictEqual(isFullSnapshot({ provider: "p", status: "available" }), false,
    "a snapshot without data is not mergeable");
  assert.strictEqual(isFullSnapshot(null), false);
  assert.strictEqual(isFullSnapshot(undefined), false);
  assert.strictEqual(isFullSnapshot("nope"), false);
  assert.strictEqual(isFullSnapshot(42), false);
}

// mergeEventData must not alias either input: the cache is read by later calls.
{
  const previous = { a: 1 };
  const incoming = { b: 2 };
  const merged = mergeEventData(previous, incoming);
  merged.a = 99;
  assert.strictEqual(previous.a, 1, "mutating the result must not corrupt the cache");
  merged.b = 98;
  assert.strictEqual(incoming.b, 2, "mutating the result must not corrupt the event");
}

console.log("ok - snapshot merge semantics");