#!/usr/bin/env node
// run-all.js — the single entry point for the NoxFlow shell test suites.
//
// The release gate used to invoke exactly one suite (test_protocol.js), so a
// regression in the island, launcher or workspace code shipped silently. This
// runner executes every *.js and *.sh suite in this directory and reports one
// summary.
//
// Usage:
//   node shell/noxflow/tests/run-all.js            # run everything
//   node shell/noxflow/tests/run-all.js --list     # list suites only
//   node shell/noxflow/tests/run-all.js test_protocol.js ...  # run a subset

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const dir = __dirname;

function discover() {
  return fs.readdirSync(dir)
    .filter((f) => /^test_.*\.(js|sh)$/.test(f))
    .filter((f) => f !== "run-all.js")
    .sort();
}

const argv = process.argv.slice(2);
const listOnly = argv.includes("--list");
const requested = argv.filter((a) => !a.startsWith("--"));
const suites = requested.length > 0 ? requested : discover();

if (listOnly) {
  suites.forEach((s) => console.log(s));
  process.exit(0);
}

if (suites.length === 0) {
  console.error("run-all: no suites found in " + dir);
  process.exit(1);
}

const results = [];
let failed = 0;

for (const suite of suites) {
  const file = path.join(dir, suite);
  if (!fs.existsSync(file)) {
    console.log(`\n── ${suite} ──────────────────────────────`);
    console.log("MISSING (suite file not found)");
    results.push({ suite, ok: false, detail: "missing" });
    failed++;
    continue;
  }

  const started = Date.now();
  let run;
  if (suite.endsWith(".js")) {
    run = spawnSync(process.execPath, [file], { encoding: "utf8" });
  } else {
    run = spawnSync("bash", [file], { encoding: "utf8" });
  }
  const elapsed = Date.now() - started;

  const output = `${run.stdout || ""}${run.stderr || ""}`;
  const ok = run.status === 0;
  if (!ok) failed++;

  results.push({ suite, ok, detail: output.trim().split("\n").slice(-1)[0] || "" });

  console.log(`\n── ${suite} ${ok ? "PASS" : "FAIL"} (${elapsed}ms) ──`);
  // Suites print their own detail; only echo output when the run failed so a
  // green run stays readable.
  if (!ok) console.log(output.trim());
}

console.log("\n══ NoxFlow shell suites ══");
results.forEach((r) => {
  console.log(`  ${r.ok ? "PASS" : "FAIL"}  ${r.suite}`);
});
console.log(`\n${results.length - failed}/${results.length} suites passed`);

if (failed > 0) {
  console.error(`run-all: ${failed} suite(s) failed`);
  process.exit(1);
}
process.exit(0);