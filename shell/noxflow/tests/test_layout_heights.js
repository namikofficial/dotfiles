#!/usr/bin/env node
// Children of ColumnLayout/RowLayout must size with Layout.preferredHeight.
//
// Qt Layouts ignore a child's `height:` and use its implicitHeight instead.
// Rectangles have implicitHeight 0, so `height: 64` inside a layout collapsed
// to nothing: dashboard tiles overlapped and were cut off, forecast cards
// overflowed upward. The tell is `height:` right next to `Layout.fill*`.
"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
function qmlFiles(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) return e.name === "tests" ? [] : qmlFiles(p);
    return e.name.endsWith(".qml") ? [p] : [];
  });
}

const offenders = [];
for (const file of qmlFiles(root)) {
  const lines = fs.readFileSync(file, "utf8").split("\n");
  let layoutLine = -100;
  lines.forEach((line, i) => {
    if (/Layout\.fill(Width|Height):\s*true/.test(line)) layoutLine = i;
    if (/^\s+height:\s/.test(line) && !/parent\.height/.test(line) && i - layoutLine <= 3) {
      offenders.push(`${path.relative(root, file)}:${i + 1}: ${line.trim()}`);
    }
  });
}

assert.deepStrictEqual(offenders, [],
  "use Layout.preferredHeight for items inside a Layout:\n  " + offenders.join("\n  "));
console.log("ok - no height: on Layout children");
