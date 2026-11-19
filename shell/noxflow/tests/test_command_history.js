const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const source = fs.readFileSync(require.resolve("../CommandHistory.js"), "utf8")
  .replace(/^\.pragma library\s*/, "");
const context = { Array, String, encodeURIComponent, decodeURIComponent };
vm.createContext(context);
vm.runInContext(source, context);

const app = { action: "launch", actionParams: { desktopId: "org.example.Editor.desktop" } };
const project = { action: "project_action", actionParams: { id: "nox origin", command: "shell" } };
assert.strictEqual(context.keyFor(app), "app:org.example.Editor.desktop");
assert.strictEqual(context.keyFor(project), "project:nox%20origin:shell");
assert.strictEqual(context.keyFor({ action: "open_settings" }), "settings");
assert.strictEqual(context.keyFor({ action: "open_clipboard" }), "clipboard");
assert.strictEqual(context.keyFor({ action: "screenshot" }), "screenshot");

for (const item of [
  { action: "copy_result", actionParams: { value: "42" } },
  { action: "focus_window", actionParams: { address: "0x1234" } },
  { action: "lock" }, { action: "suspend" }, { action: "reboot" },
  { action: "power_off" }, { action: "reload_shell" },
  { action: "launch", actionParams: { command: "arbitrary command" } },
  { action: "launchProgram", actionParams: { program: "systemctl; reboot" } },
  { action: "project_action", actionParams: { id: "x", command: "delete" } },
]) assert.strictEqual(context.keyFor(item), "");

const keys = [context.keyFor(project), context.keyFor(app), context.keyFor(project), "bad:key"];
assert.deepStrictEqual(Array.from(context.normalize(keys)), [context.keyFor(project), context.keyFor(app)]);
assert.strictEqual(context.position(keys, app), 1);
assert.strictEqual(context.position(keys, { action: "lock" }), -1);

const many = Array.from({ length: 10 }, (_, i) => "app:app" + i + ".desktop");
assert.strictEqual(context.normalize(many).length, 8);
assert.deepStrictEqual(Array.from(context.normalize(["clipboard", "clipboard", "settings"])), ["clipboard", "settings"]);
assert.deepStrictEqual(Array.from(context.normalize({ commands: ["clipboard"] })), []);

console.log("noxflow command history fixtures passed");
