const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const source = fs.readFileSync(
  require.resolve("../surfaces/dashboard/DashboardClock.js"),
  "utf8"
).replace(/^\.pragma library\s*/, "");
const context = { Date, Math, Number, isFinite, isNaN };
vm.createContext(context);
vm.runInContext(source, context);

for (let h = 0; h < 24; h++) {
  const got = context.greetingForHour(h);
  const expected = h >= 5 && h < 12 ? "Good morning"
    : h >= 12 && h < 17 ? "Good afternoon"
    : h >= 17 ? "Good evening"
    : "Late night";
  assert.strictEqual(got, expected, `hour ${h} greeting`);
}

assert.strictEqual(
  context.greetingForDate(new Date(2026, 10, 20, 0, 31, 0)),
  "Late night",
  "00:31 must greet as Late night, not Good morning"
);

const dashboardQml = fs.readFileSync(require.resolve("../surfaces/dashboard/Dashboard.qml"), "utf8");
assert(dashboardQml.includes("property date now: new Date()"), "Dashboard must own reactive root.now");
assert(dashboardQml.includes("id: clockRefreshTimer"), "Dashboard must refresh root.now on a timer");
assert(dashboardQml.includes("DashboardClock.greetingForDate(root.now)"),
  "Dashboard greeting must depend explicitly on root.now");
assert(dashboardQml.includes('Qt.formatDate(root.now, "dddd, MMMM d")'),
  "Dashboard date subtitle must depend explicitly on root.now");
assert(!dashboardQml.includes("ScrollBar.AlwaysOn"), "Dashboard must use AsNeeded scrollbar");
assert(!/Qt\.formatDate\(new Date\(\)/.test(dashboardQml), "Dashboard date must not read unreactive new Date()");

console.log("ok - dashboard time-of-day greeting and reactive clock fixtures passed");
