const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const source = fs.readFileSync(
  require.resolve("../surfaces/notifications/NotificationGrouping.js"),
  "utf8"
).replace(/^\.pragma library\s*/, "");
const context = { Array, String, Math, Number };
vm.createContext(context);
vm.runInContext(source, context);

assert.deepStrictEqual(Array.from(context.groupByApp([])), []);
assert.deepStrictEqual(Array.from(context.groupByApp(null)), []);

const grouped = context.groupByApp([
  { id: "1", app_name: "Build" },
  { id: "2", app_name: "Mail" },
  { id: "3", app_name: "build" },
  { id: "4", app_name: "" }
]);

assert.strictEqual(grouped.length, 3, "groups case-insensitively and preserves first appearance order");
assert.strictEqual(grouped[0].appName, "Build");
assert.strictEqual(grouped[0].count, 2);
assert.deepStrictEqual(Array.from(grouped[0].items, (x) => x.id), ["1", "3"]);
assert.strictEqual(grouped[1].appName, "Mail");
assert.strictEqual(grouped[2].appName, "System", "empty app_name falls back to System");

const emptyHeight = context.estimatePanelHeight(0, false, (v) => v);
const redactedHeight = context.estimatePanelHeight(4, true, (v) => v);
const populatedHeight = context.estimatePanelHeight(3, false, (v) => v);
assert(emptyHeight < 360, `empty notification panel must stay compact (got ${emptyHeight})`);
assert(redactedHeight < 360, `redacted notification panel must stay compact (got ${redactedHeight})`);
assert(populatedHeight > emptyHeight, "populated height estimate grows above empty height");

const modelQml = fs.readFileSync(require.resolve("../NotificationModel.qml"), "utf8");
assert(!/^\s*history\s*=\s*history\s*;/m.test(modelQml), "NotificationModel must not shadow root.history with local history = history;");
assert(modelQml.includes("function removeFromHistory("), "NotificationModel must expose removeFromHistory()");
assert(modelQml.includes("dedupePrependHistory("), "NotificationModel must deduplicate history entries");

const bridgeQml = fs.readFileSync(require.resolve("../services/NotificationBridge.qml"), "utf8");
assert(bridgeQml.includes("timestamp:"), "NotificationBridge must populate arrival timestamp for NotificationItem");
assert(bridgeQml.includes("pushHistory("), "NotificationBridge must archive dismissed/expired items into history");
assert(/actionsSupported:\s*true/.test(bridgeQml), "NotificationBridge must advertise actionsSupported for inline actions");
assert(/n\.tracked\s*=\s*true/.test(bridgeQml), "NotificationBridge must track notifications so metadata stays intact");

const centreQml = fs.readFileSync(require.resolve("../surfaces/notifications/NotificationCentre.qml"), "utf8");
assert(centreQml.includes("preferredHeight"), "NotificationCentre must expose content-aware preferredHeight");
assert(centreQml.includes("Grouping.groupByApp("), "NotificationCentre must group notifications by app");
assert(centreQml.includes("bridge.dismiss("), "NotificationCentre must dismiss via NotificationBridge");

const morphQml = fs.readFileSync(require.resolve("../core/MorphSurface.qml"), "utf8");
assert(morphQml.includes("preferredHeight"), "MorphSurface must read notification preferredHeight");
assert(morphQml.includes("function syncContentHeight()"), "MorphSurface must sync dynamic notification height");

console.log("ok - notification centre grouping, history, and content-aware sizing fixtures passed");
