// test_model_utils.js — ModelUtils.asArray regression coverage.
//
// Why this test exists: every daemon-fed model normalised its snapshot lists
// with `Array.isArray(x) ? x : []`. noxd snapshots reach QML as QML *sequence*
// objects, which report `constructor === Array` and a correct `length` but
// return **false** from `Array.isArray()`. Every one of those guards therefore
// replaced live daemon data with an empty list.
//
// The visible symptom was not an error: the workspace strip, the Wi-Fi list,
// the Bluetooth device count, the power-profile list, media players,
// notification items and transfer devices all rendered as permanently empty
// while `noxctl status` reported every provider as Available.

const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const context = { isFinite, isNaN, Math, Number, String, Array, Object, JSON };
vm.createContext(context);
// `.pragma library` is a QML directive, not JavaScript.
vm.runInContext(
  fs.readFileSync(require.resolve("../ModelUtils.js"), "utf8").replace(/^\.pragma.*$/gm, ""),
  context);
const asArray = context.asArray;

// ── The regression itself ──
// A QML sequence object: array-like, correct length, NOT Array.isArray.
// This is the exact shape that made the old guards discard real data.
function qmlSequence(values) {
  const seq = { length: values.length };
  values.forEach((v, i) => { seq[i] = v; });
  Object.defineProperty(seq, "constructor", {
    value: Array, enumerable: false, writable: true, configurable: true,
  });
  assert.strictEqual(Array.isArray(seq), false, "fixture must fail Array.isArray");
  assert.strictEqual(seq.length, values.length, "fixture must report its length");
  return seq;
}

// ── Native arrays still pass through ──
const native = [1, 2, 3];
assert.strictEqual(asArray(native), native, "a native array is returned as-is");
assert(Array.isArray(asArray(native)), "native arrays stay native");

// ── Sequence objects are converted, not discarded ──
const ws = qmlSequence([{ name: "1" }, { name: "2" }, { name: "3" }]);
const out = asArray(ws);
assert.strictEqual(out.length, 3, "sequence length is preserved");
assert.deepStrictEqual(Array.from(out), Array.from(ws), "sequence contents are preserved");
assert.strictEqual(Array.isArray(out), true, "the result is a real array");
assert.notStrictEqual(out, ws, "the result is a copy, not the sequence itself");
// The copy must be mutable without touching the source sequence.
out[0] = "mutated";
assert.notStrictEqual(ws[0], "mutated", "the source sequence is not aliased");

// A sequence of primitives must not degrade to "[object Object]".
const names = qmlSequence(["1", "2"]);
assert.deepStrictEqual(Array.from(asArray(names)), ["1", "2"],
  "primitive sequence elements survive conversion");

// ── Empty and absent values ──
// asArray runs inside the vm realm, so its arrays have that realm's prototype.
// Array.from() normalises back into this realm before deepStrictEqual.
assert.deepStrictEqual(Array.from(asArray(qmlSequence([]))), [], "an empty sequence is an empty array");
assert.deepStrictEqual(Array.from(asArray(null)), [], "null is an empty array");
assert.deepStrictEqual(Array.from(asArray(undefined)), [], "undefined is an empty array");
assert.deepStrictEqual(Array.from(asArray({})), [], "a plain object is not a list");

// ── The models must use the helper, not Array.isArray ──
// A stray Array.isArray on a snapshot field reintroduces the whole bug, so
// this is a source-level guard rather than a runtime one.
const fs2 = require("fs");
const path = require("path");
const root = path.join(__dirname, "..");
const models = [
  "HyprlandModel.qml", "AudioModel.qml", "MediaModel.qml", "NetworkModel.qml",
  "PowerModel.qml", "SyncthingModel.qml", "TransferModel.qml",
  "BluetoothModel.qml", "NotificationModel.qml",
];
for (const model of models) {
  const src = fs2.readFileSync(path.join(root, model), "utf8");
  assert(!/Array\.isArray\(/.test(src),
    `${model} must not gate a snapshot list on Array.isArray`);
}
assert(/asArray/.test(fs2.readFileSync(path.join(root, "HyprlandModel.qml"), "utf8")),
  "HyprlandModel must use ModelUtils.asArray");

console.log("model utils: asArray handles QML sequence objects");