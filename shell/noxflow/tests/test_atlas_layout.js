const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const source = fs.readFileSync(require.resolve("../surfaces/atlas/AtlasLayout.js"), "utf8")
  .replace(/^\.pragma library\s*/, "");
const context = { Math, Number };
vm.createContext(context);
vm.runInContext(source, context);

// 1..6 workspaces on 1920x1080 viewport (~1690x860 grid).
assert.strictEqual(context.computeGrid(1, 1690, 860, 360, 260, 4).columns, 1);
assert.strictEqual(context.computeGrid(2, 1690, 860, 360, 260, 4).columns, 2);
assert.strictEqual(context.computeGrid(3, 1690, 860, 360, 260, 4).columns, 3);
assert.strictEqual(context.computeGrid(4, 1690, 860, 360, 260, 4).columns, 2);

const five = context.computeGrid(5, 1690, 860, 360, 260, 4);
assert.strictEqual(five.columns, 3, "5 workspaces keep the 3+2 layout");
assert.strictEqual(five.rows, 2);
assert.strictEqual(five.scrolls, false);

// High workspace counts across common screen sizes and scales never shrink cards below minCardHeight.
const viewports = [
  { name: "1080p@1.0", w: 1690, h: 860 },
  { name: "1080p@1.5", w: 1126, h: 540 },
  { name: "1440p@1.0", w: 2252, h: 1180 },
  { name: "portrait", w: 950, h: 1600 },
  { name: "narrow", w: 620, h: 800 }
];

for (const vp of viewports) {
  for (const count of [8, 10, 12, 16]) {
    const g = context.computeGrid(count, vp.w, vp.h, 360, 260, 4);
    assert(g.columns >= 1 && g.columns <= 4, `${vp.name} n=${count}: valid columns (${g.columns})`);
    assert(g.cellHeight >= 260, `${vp.name} n=${count}: cellHeight ${g.cellHeight} >= 260`);
    assert(g.columns * g.cellWidth <= vp.w, `${vp.name} n=${count}: row fits inside gridWidth`);
    assert.strictEqual(g.scrolls, (g.rows * g.cellHeight) > vp.h, `${vp.name} n=${count}: scrolls flag accurate`);
  }
}

assert.strictEqual(context.computeGrid(12, 1126, 540, 360, 260, 4).scrolls, true,
  "12 workspaces at scaled 1080p must scroll rather than cramp");
assert.strictEqual(context.computeGrid(16, 1690, 860, 360, 260, 4).scrolls, true,
  "16 workspaces at 1080p must scroll rather than cramp");

const atlasQml = fs.readFileSync(require.resolve("../surfaces/atlas/Atlas.qml"), "utf8");
assert(atlasQml.includes("AtlasLayout.computeGrid("), "Atlas.qml must compute grid via AtlasLayout.computeGrid");
assert(/function stepWorkspace[\s\S]*?positionViewAtIndex\(next,\s*GridView\.Contain\)/.test(atlasQml),
  "stepWorkspace must scroll off-screen workspaces into view");

console.log("ok - atlas layout high-workspace-count and scroll fixtures passed");
