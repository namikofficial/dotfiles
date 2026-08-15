const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const context = { isFinite, isNaN, Math, Number, String };
vm.createContext(context);
vm.runInContext(fs.readFileSync(require.resolve("../SystemSnapshot.js"), "utf8"), context);

const first = context.parseSnapshot(
  "CPU=100 0 50 800 20 5 5 0\nMEM=16000 6000\nDISK=25000 100000\nTEMP=67500\nGPU=42|2048|8192|RTX 4050\n",
  null
);
assert(first.ok);
assert.strictEqual(first.memUsed, 10000);
assert.strictEqual(first.memPercent, 63);
assert.strictEqual(first.diskPercent, 25);
assert.strictEqual(first.cpuTemp, 68);
assert.strictEqual(first.gpuAvailable, true);

const second = context.parseSnapshot(
  "CPU=130 0 70 850 20 5 5 0\nMEM=16000 5000\nDISK=26000 100000\nTEMP=NA\nGPU=NA\n",
  { cpuUsage: first.cpuUsage, cpuIdle: first.cpuIdle, cpuTotal: first.cpuTotal }
);
assert(second.ok);
assert.strictEqual(second.cpuUsage, 50);
assert.strictEqual(second.cpuTemp, 0);
assert.strictEqual(second.gpuAvailable, false);

const malformed = context.parseSnapshot("CPU=broken\nMEM=0 0\n", second);
assert.strictEqual(malformed.ok, false);

let current = second;
if (malformed.ok) current = malformed;
assert.strictEqual(current.memUsed, second.memUsed, "invalid samples must not replace the last valid sample");
assert.strictEqual(current.cpuUsage, second.cpuUsage);

console.log("noxflow system snapshot parser fixtures passed");
