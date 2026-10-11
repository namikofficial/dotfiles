#!/usr/bin/env node
// Design-token rules that used to drift.
//   * The type scale is seven roles, not twelve near-duplicate steps.
//   * Control borders (outlineDefault) meet WCAG 3:1 non-text contrast on
//     surfaceContainerHigh, statically and after runtime/profile theming.
//   * Reduced motion has one source: Tokens.reducedMotion.
//   * Animation timings live in one table (Tokens' motion block).
"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const tokens = fs.readFileSync(path.join(root, "theme/Tokens.qml"), "utf8");

const sizes = new Set([...tokens.matchAll(/readonly property int typography\w+:\s*(\d+)/g)].map((m) => m[1]));
assert.ok(sizes.size <= 7, `type scale has ${sizes.size} distinct sizes: ${[...sizes].join(", ")}`);

function hex(name) {
  const m = tokens.match(new RegExp(`property color ${name}:\\s*"(#[0-9A-Fa-f]{6})"`));
  assert.ok(m, `${name} has a static hex default`);
  return m[1];
}
function lum(h) {
  const ch = (i) => {
    const v = parseInt(h.slice(i, i + 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * ch(1) + 0.7152 * ch(3) + 0.0722 * ch(5);
}
const a = lum(hex("outlineDefault"));
const b = lum(hex("surfaceSurfaceContainerHigh"));
const ratio = (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
assert.ok(ratio >= 3, `static outlineDefault contrast ${ratio.toFixed(2)} < 3`);
assert.strictEqual((tokens.match(/outlineDefault\s*=\s*ensureContrast\(/g) || []).length, 2,
  "runtime and profile theming both lift outlineDefault through ensureContrast");

const motion = fs.readFileSync(path.join(root, "config/Motion.qml"), "utf8");
const shellConfig = fs.readFileSync(path.join(root, "config/ShellConfig.qml"), "utf8");
assert.ok(/Theme\.Tokens\.reducedMotion/.test(motion), "Motion reads Tokens.reducedMotion");
assert.ok(!/reduceMotion/.test(shellConfig), "ShellConfig no longer has its own reduceMotion");

// One motion table: timings are numbers only in Tokens' motion block.
assert.ok(!/scaled\(\s*\d/.test(motion) && !/Math\.round\(\s*\d+\s*\*/.test(motion),
  "Motion.qml derives durations from Tokens, it holds no timing literals");
assert.ok(!/duration\(\s*\d+\s*\)/.test(tokens), "Tokens animations use named motion tokens, not literals");
const lifecycle = fs.readFileSync(path.join(root, "components/SurfaceLifecycle.qml"), "utf8");
assert.ok(/Tokens\.motionSurface/.test(lifecycle), "SurfaceLifecycle uses the motion table");

console.log(`ok - design tokens (${sizes.size} type sizes, outline ${ratio.toFixed(2)}:1)`);
