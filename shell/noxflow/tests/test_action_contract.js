// test_action_contract.js — every action the shell sends must be a real daemon
// action.
//
// Why this test exists: `Capture.qml` sent `ai_query`, which is not a variant
// of `Action` in core/noxflow-ipc/src/lib.rs. noxd rejected it with
// `invalid_request` and the button did nothing. Nothing caught it: the shell's
// 14 suites are static, `qmllint` does not resolve the daemon's wire format,
// and noxd's own tests only cover actions its Rust code constructs.
//
// `test_action_routing.sh` guards four specific names that were known to be
// wrong. This test is the general form: it enumerates every action name at
// every `runAction(` / `sendAction(` call site and requires each one to exist
// in the daemon's `Action` enum. A new invalid action fails here instead of
// becoming a dead button.

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..", "..", "..");
const shellDir = path.join(root, "shell", "noxflow");
const ipcSrc = path.join(root, "core", "noxflow-ipc", "src", "lib.rs");

// ── 1. The daemon's Action variants ─────────────────────────────────────────
// `#[serde(rename_all = "snake_case")]` means `AudioToggleMute` is
// `audio_toggle_mute` on the wire. Doc comments and attributes between the
// enum header and the closing brace are skipped.
const rust = fs.readFileSync(ipcSrc, "utf8");
const enumMatch = rust.match(/pub enum Action \{([\s\S]*?)\n\}/);
assert(enumMatch, "core/noxflow-ipc/src/lib.rs must declare `pub enum Action`");

const snake = (name) => name.replace(/([a-z0-9])([A-Z])/g, "$1_$2").toLowerCase();

const daemonActions = new Set();
for (const raw of enumMatch[1].split("\n")) {
  const line = raw.trim();
  if (!line || line.startsWith("//") || line.startsWith("#[")) continue;
  const m = line.match(/^([A-Z][A-Za-z0-9]*)\b/);
  if (m) daemonActions.add(snake(m[1]));
}
assert(daemonActions.size >= 30,
  `expected the daemon to declare a substantial Action enum, parsed ${daemonActions.size}`);

// ── 2. Every action name the shell sends ───────────────────────────────────
// Call sites look like `runAction({ audio_toggle_mute: { target: "output" } })`
// and `sendAction({ lock: {} })`. Both the externally-tagged object form and the
// bare-string form are accepted by the daemon, so both are collected.
function qmlFiles(dir, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "tests") continue; // the tests assert on these very strings
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) qmlFiles(full, acc);
    else if (/\.(qml|js)$/.test(entry.name)) acc.push(full);
  }
  return acc;
}

const CALL = /\b(?:runAction|sendAction)\s*\(\s*\{\s*([a-z][a-z0-9_]*)\s*:/g;
const STRING_CALL = /\b(?:runAction|sendAction)\s*\(\s*"([a-z][a-z0-9_]*)"/g;

const sent = new Map(); // action -> [file:line, ...]
for (const file of qmlFiles(shellDir)) {
  const src = fs.readFileSync(file, "utf8");
  const lines = src.split("\n");
  lines.forEach((line, i) => {
    // A commented-out line is not a call site.
    if (/^\s*\/\//.test(line)) return;
    for (const re of [CALL, STRING_CALL]) {
      re.lastIndex = 0;
      let m;
      while ((m = re.exec(line)) !== null) {
        const name = m[1];
        if (!sent.has(name)) sent.set(name, []);
        sent.get(name).push(`${path.relative(root, file)}:${i + 1}`);
      }
    }
  });
}

assert(sent.size >= 20,
  `expected the shell to send many actions, found ${sent.size}`);

// ── 3. The contract ─────────────────────────────────────────────────────────
const unknown = [...sent.entries()].filter(([name]) => !daemonActions.has(name));

if (unknown.length > 0) {
  const lines = ["The shell sends actions noxd does not accept. noxd returns",
    "invalid_request for each, so the UI control silently does nothing.",
    ""];
  for (const [name, where] of unknown) {
    lines.push(`  ${name}`);
    for (const loc of where) lines.push(`      ${loc}`);
    const near = [...daemonActions].filter((a) => {
      const al = a.split("_"), nl = name.split("_");
      return al.length === nl.length && al.every((p, i) => p[0] === nl[i][0]);
    });
    if (near.length > 0) lines.push(`      did you mean: ${near.join(", ")}`);
  }
  lines.push("", `Daemon actions: ${[...daemonActions].sort().join(" ")}`);
  throw new Error("\n" + lines.join("\n"));
}

// ── 4. Sanity: the names this suite cares about really are daemon actions ──
// Otherwise a refactor could empty the shell's call sites and this test would
// pass vacuously.
for (const expected of ["audio_toggle_mute", "audio_adjust_volume", "lock",
                        "power_profile_set", "network_refresh", "media_next",
                        "brightness_set", "transfer_discover"]) {
  assert(daemonActions.has(expected), `daemon must accept ${expected}`);
}
assert(!daemonActions.has("ai_query"),
  "ai_query must stay rejected; the shell routes AI through services/AiClient.qml");

console.log(
  `action contract: ${sent.size} shell actions all exist in the daemon Action enum`);