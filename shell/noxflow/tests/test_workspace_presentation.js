const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const context = { String };
vm.createContext(context);
vm.runInContext(fs.readFileSync(require.resolve("../WorkspacePresentation.js"), "utf8"), context);

assert.strictEqual(context.workspaceId({ id: 7, name: "dev" }), "dev");
assert.strictEqual(context.workspaceId({ id: 7 }), "7");
assert.strictEqual(context.applicationName({ application_id: "com.visual-studio_code" }), "Visual studio code");
assert.strictEqual(context.windowTitle({ title: "  Issue, 42  " }), "Issue, 42");
assert(context.activeWindowMatches("3", "eDP-1", "eDP-1", { name: "3" }, { title: "Editor" }));
assert(!context.activeWindowMatches("3", "HDMI-A-1", "eDP-1", { name: "3" }, { title: "Editor" }));
assert(context.activeWindowMatches("4", "HDMI-A-1", "eDP-1", { name: "3" }, { workspace: { name: "4" } }));
assert.strictEqual(context.tooltip("3", true, true, "Code", "README.md"), "Workspace 3 · active · Code · README.md");
assert.strictEqual(context.tooltip("2", false, false, "", ""), "Workspace 2");

console.log("noxflow workspace presentation fixtures passed");
