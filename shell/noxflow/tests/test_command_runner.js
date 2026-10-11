#!/usr/bin/env node
// Command.qml must be re-runnable.
//
// It used to bind `Process.running: root.running`. A Process clears its own
// `running` when the program exits, which silently broke that binding and left
// `root.running` true forever: run() refused every later call, so all 39
// Command users (system telemetry, night light, Syncthing actions, ...) worked
// exactly once per shell lifetime and the dashboard showed hours-old data.
// QML cannot be executed here, so this pins the source-level contract.
"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const command = fs.readFileSync(path.join(root, "components/Command.qml"), "utf8");

assert.ok(!/^\s*running:\s*root\.running\b/m.test(command),
  "Process.running must not be a binding to root.running (it breaks on exit)");
assert.ok(/onExited:[\s\S]*?root\.running\s*=\s*false[\s\S]*?root\.exited\(/.test(command),
  "onExited clears root.running before emitting exited()");
assert.ok(/onRunningChanged:\s*\{?\s*if\s*\(proc\.running !== root\.running\)/.test(command),
  "setting Command.running = true starts the process");

const system = fs.readFileSync(path.join(root, "SystemModel.qml"), "utf8");
const poll = system.slice(system.indexOf("function pollAll()"));
assert.ok(/snapshotProcess\.output\s*=\s*""[\s\S]*?snapshotProcess\.running\s*=\s*true/.test(poll),
  "pollAll clears the previous snapshot output before starting the next one");

assert.ok(/Qt\.callLater\(function\(\)\s*\{\s*if \(root\.running && !proc\.running\) root\.running = false;/.test(command),
  "a start rejected without a running signal does not leave the runner stuck");

console.log("ok - Command runner is re-runnable");
