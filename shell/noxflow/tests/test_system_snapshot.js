const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const context = { isFinite, isNaN, Math, Number, String };
vm.createContext(context);
vm.runInContext(fs.readFileSync(require.resolve("../SystemSnapshot.js"), "utf8"), context);

// ── Baseline: NVIDIA GPU, all extended metrics present ──
const first = context.parseSnapshot(
  "CPU=100 0 50 800 20 5 5 0\n" +
    "MEM=16000 6000\n" +
    "DISK=25000 100000\n" +
    "TEMP=67500\n" +
    "GPU=42|2048|8192|36.4|49|RTX 4050 Laptop GPU|nvidia|0\n",
  null
);
assert(first.ok, "first snapshot parses");
assert.strictEqual(first.memUsed, 10000);
assert.strictEqual(first.memPercent, 63);
assert.strictEqual(first.diskPercent, 25);
assert.strictEqual(first.cpuTemp.available, true);
assert.strictEqual(first.cpuTemp.value, 68);
assert.strictEqual(first.gpuAvailable, true);
assert.strictEqual(first.gpuSource, "nvidia");
assert.strictEqual(first.gpuSourceId, "0");
assert.strictEqual(first.gpuName, "RTX 4050 Laptop GPU");
assert.strictEqual(first.gpuPower.available, true);
assert.strictEqual(first.gpuPower.value, 36.4);
assert.strictEqual(first.gpuTemp.available, true);
assert.strictEqual(first.gpuTemp.value, 49);

// ── Extended: load avg, freq, swap, plus GPU name+sourceId ──
const extended = context.parseSnapshot(
  "CPU=140 0 80 900 20 5 5 0\n" +
    "MEM=32000 24000\n" +
    "SWAP=8000 7000\n" +
    "DISK=50000 100000\n" +
    "TEMP=52000\n" +
    "FREQ=2400\n" +
    "LOAD=0.31 0.42 0.48\n" +
    "GPU=45|6144|16384|36.4|49|RTX 4050 Laptop GPU|nvidia|0\n",
  { cpuUsage: first.cpuUsage, cpuIdle: first.cpuIdle, cpuTotal: first.cpuTotal }
);
assert(extended.ok);
assert.strictEqual(extended.cpuFreq.available, true);
assert.strictEqual(extended.cpuFreq.value, 2400);
assert.strictEqual(extended.load1.available, true);
assert.strictEqual(extended.load1.value, 0.31);
assert.strictEqual(extended.load5.available, true);
assert.strictEqual(extended.load5.value, 0.42);
assert.strictEqual(extended.load15.available, true);
assert.strictEqual(extended.load15.value, 0.48);
assert.strictEqual(extended.swapUsed.available, true);
assert.strictEqual(extended.swapUsed.value, 1000);
assert.strictEqual(extended.swapTotal.available, true);
assert.strictEqual(extended.swapTotal.value, 8000);
assert.strictEqual(extended.gpuName, "RTX 4050 Laptop GPU");
assert.strictEqual(extended.gpuPower.available, true);
assert.strictEqual(extended.gpuPower.value, 36.4);
assert.strictEqual(extended.gpuTemp.available, true);
assert.strictEqual(extended.gpuTemp.value, 49);

// ── Comma in NVIDIA GPU name must round-trip without corruption ──
const commaName = context.parseSnapshot(
  "CPU=140 0 80 900 20 5 5 0\n" +
    "MEM=32000 24000\n" +
    "DISK=50000 100000\n" +
    "GPU=45|6144|16384|36.4|49|NVIDIA, GeForce RTX 4050 Laptop GPU|nvidia|0\n",
  null
);
assert(commaName.ok, "comma-name snapshot parses");
assert.strictEqual(commaName.gpuName, "NVIDIA, GeForce RTX 4050 Laptop GPU",
    "commas in GPU names must survive the parser");
assert.strictEqual(commaName.gpuSource, "nvidia");

// ── Integrated GPU: no nvidia-smi, sysfs fallback ──
const integrated = context.parseSnapshot(
  "CPU=120 0 60 850 20 5 5 0\n" +
    "MEM=32000 24000\n" +
    "DISK=50000 100000\n" +
    "TEMP=52000\n" +
    "GPU=23|0|0|0|0|Integrated GPU|integrated|card0\n",
  null
);
assert(integrated.ok);
assert.strictEqual(integrated.gpuAvailable, true);
assert.strictEqual(integrated.gpuSource, "integrated");
assert.strictEqual(integrated.gpuSourceId, "card0");
assert.strictEqual(integrated.gpuUsage, 23);
assert.strictEqual(integrated.gpuPower.available, false,
    "integrated GPU has no power telemetry");
assert.strictEqual(integrated.gpuTemp.available, false,
    "integrated GPU has no temperature telemetry");

// ── Missing metrics become unavailable, not stale 0 ──
const second = context.parseSnapshot(
  "CPU=130 0 70 850 20 5 5 0\n" +
    "MEM=16000 5000\n" +
    "DISK=26000 100000\n" +
    "TEMP=NA\n" +
    "FREQ=NA\n" +
    "GPU=NA\n",
  { cpuUsage: first.cpuUsage, cpuIdle: first.cpuIdle, cpuTotal: first.cpuTotal }
);
assert(second.ok, "partial snapshot still parses");
assert.strictEqual(second.cpuUsage, 50);
assert.strictEqual(second.cpuTemp.available, false,
    "missing temperature must be unavailable, not a stale 0");
assert.strictEqual(second.cpuFreq.available, false,
    "missing frequency must be unavailable, not a stale 0");
assert.strictEqual(second.swapUsed.available, false,
    "missing swap must be unavailable, not 0");
assert.strictEqual(second.swapTotal.available, false);
assert.strictEqual(second.gpuAvailable, false);
assert.strictEqual(second.gpuSource, "none");
assert.strictEqual(second.gpuPower.available, false,
    "absent GPU line must clear GPU power availability");
assert.strictEqual(second.gpuTemp.available, false,
    "absent GPU line must clear GPU temp availability");
assert.strictEqual(second.load1.available, false,
    "absent load average must be unavailable");
assert.strictEqual(second.load5.available, false);
assert.strictEqual(second.load15.available, false);

// ── Malformed snapshot must fail validation, never silently overwrite ──
const malformed = context.parseSnapshot("CPU=broken\nMEM=0 0\n", second);
assert.strictEqual(malformed.ok, false);
let current = second;
if (malformed.ok) current = malformed;
assert.strictEqual(current.memUsed, second.memUsed,
    "invalid samples must not replace the last valid sample");
assert.strictEqual(current.cpuUsage, second.cpuUsage);

// ── GPU line with missing fields must not be accepted as valid ──
const partialGpu = context.parseSnapshot(
  "CPU=130 0 70 850 20 5 5 0\n" +
    "MEM=16000 5000\n" +
    "DISK=26000 100000\n" +
    "GPU=42|2048|8192\n",
  null
);
assert.strictEqual(partialGpu.ok, true, "CPU/MEM/DISK must still parse");
assert.strictEqual(partialGpu.gpuAvailable, false,
    "truncated GPU line must not be marked available");

// ── Load average with non-numeric value must be unavailable, not crash ──
const badLoad = context.parseSnapshot(
  "CPU=130 0 70 850 20 5 5 0\n" +
    "MEM=16000 5000\n" +
    "DISK=26000 100000\n" +
    "LOAD=NaN 0.5 0.6\n",
  null
);
assert(badLoad.ok);
assert.strictEqual(badLoad.load1.available, false,
    "non-numeric load averages must be flagged unavailable");

// ── Swap with non-numeric total must be unavailable, not corrupt ──
const badSwap = context.parseSnapshot(
  "CPU=130 0 70 850 20 5 5 0\n" +
    "MEM=16000 5000\n" +
    "DISK=26000 100000\n" +
    "SWAP=abc 1000\n",
  null
);
assert(badSwap.ok);
assert.strictEqual(badSwap.swapUsed.available, false);
assert.strictEqual(badSwap.swapTotal.available, false);

// ── Freshness helper ──
assert.strictEqual(context.freshness(0, 0, 10000, false), "unavailable");
assert.strictEqual(context.freshness(5000, 0, 10000, true), "live");
assert.strictEqual(context.freshness(15000, 0, 10000, true), "stale");
assert.strictEqual(context.freshness(15000, 5000, 10000, false), "stale",
    "a failed refresh preserves a prior reading only as explicitly stale");
assert.strictEqual(context.freshness(0, 0, 10000, true), "live",
    "first snapshot at t=0 with no elapsed time is live");

// ── NVIDIA GPU name with reserved separators must be preserved ──
const pipeName = context.parseSnapshot(
  "CPU=130 0 70 850 20 5 5 0\n" +
    "MEM=16000 5000\n" +
    "DISK=26000 100000\n" +
    "GPU=42|2048|8192|36.4|49|GeForce|RTX|4050|nvidia|0\n",
  null
);
assert(pipeName.ok);
assert.strictEqual(pipeName.gpuSource, "nvidia");
assert.strictEqual(pipeName.gpuSourceId, "0");
assert(pipeName.gpuName.indexOf("GeForce") >= 0,
    "GPU names with multiple pipe-split segments must still recover the name");

console.log("noxflow system snapshot parser fixtures passed");
