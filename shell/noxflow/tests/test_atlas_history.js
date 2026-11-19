const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const source = fs.readFileSync(require.resolve("../surfaces/atlas/AtlasHistory.js"), "utf8")
  .replace(/^\.pragma library\s*/, "");
const context = { Array, String };
vm.createContext(context);
vm.runInContext(source, context);

let history = [];
history = context.record(history, {
  address: "0x1", title: "README.md - Code", application_id: "com.visual-studio_code",
  workspace: { id: 3 },
});
history = context.record(history, {
  address: "0x2", title: "Design board", class: "org.inkscape.Inkscape", workspace: "4",
});
assert.deepStrictEqual(Array.from(history, (entry) => entry.address), ["0x2", "0x1"]);
assert.strictEqual(history[0].app, "Inkscape");
assert.strictEqual(history[0].workspaceId, "4");

history = context.record(history, { address: "0x1", title: "Updated README", appid: "code" });
assert.deepStrictEqual(Array.from(history, (entry) => entry.address), ["0x1", "0x2"]);
assert.strictEqual(history[0].title, "Updated README");
assert.strictEqual(context.record(history, { address: "not-an-address", title: "ignored" }), history);

for (let i = 3; i <= 9; i++) history = context.record(history, { address: "0x" + i, title: "Window " + i });
assert.strictEqual(history.length, 5);
assert.strictEqual(history[0].address, "0x9");
assert.strictEqual(history[4].address, "0x5");

console.log("noxflow Atlas focus history fixtures passed");
