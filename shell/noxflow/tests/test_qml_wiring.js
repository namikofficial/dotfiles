// test_qml_wiring.js — static guards for three defects that made working
// features render as permanently empty while every visible signal said "fine".
//
// None of these produced an error the shell's own load check could see. Each
// one silently produced zero delegates, or fed a bar a value that could never
// change. They are worth a test precisely because no runtime check catches
// them.
//
// 1. Shadowed ids. `shell.qml` declared `NotificationModel { id: notificationModel }`
//    and then wrote `notificationModel: notificationModel`, where the left side
//    is TopChrome's property and the right side resolved to that same property
//    instead of the id. TopChrome received `undefined`, so the bar's notification
//    badge read `undefined.length` and rendered a permanent 0.
// 2. Types that no longer exist. `NotificationItem.qml` used Quickshell's
//    `FrameAnimation`, which is not an exported type in Quickshell 0.3.2. The
//    component could not be instantiated, so the notification centre drew its
//    header and its "Active (2)" tab count over an empty body.
// 3. Circular measurement. `NotificationItem` declared
//    `implicitHeight: layout.height` while `layout` was `anchors.fill: parent`.
//    The card measured to zero, so every card in the list collapsed onto one
//    point.
//
// This test is deliberately text-based: it needs no Quickshell runtime, which is
// what makes it safe to run in the release gate.

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const shellRoot = path.resolve(__dirname, "..");

function qmlFiles(dir) {
  const out = [];
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    const stat = fs.statSync(full);
    if (stat.isDirectory()) {
      if (name === "tests") continue;
      out.push(...qmlFiles(full));
    } else if (name.endsWith(".qml")) {
      out.push(full);
    }
  }
  return out;
}

const allQml = qmlFiles(shellRoot);

// ── 1. A binding must not resolve a sibling id to itself ──
//
// Shape: `foo: foo` where `foo` is also the id of an object in the same file,
// *and* `foo` is a declared property of the component being instantiated there.
// QML resolves a property name ahead of an id, so the right-hand side binds to
// the property being assigned rather than to the object the author meant, and
// the target silently receives `undefined`.
//
// Both extra conditions matter. Without the id check, ordinary JavaScript object
// literals match (`model: model` inside a JSON.stringify({...}) argument is a
// key/value pair). Without the property check, legitimate plumbing matches —
// `root: root` inside `IslandQueueHost { }` correctly passes this file's `root`
// id to that child's `root` property.
const byBasename = new Map();
for (const file of allQml) byBasename.set(path.basename(file), file);

function declaredProperties(file) {
  const text = fs.readFileSync(file, "utf8");
  const props = new Set();
  for (const m of text.matchAll(
    /^\s*(?:required\s+)?property\s+(?:var|[A-Za-z][A-Za-z0-9_.<>]*)\s+([a-z][A-Za-z0-9_]*)\s*:/gm)) {
    props.add(m[1]);
  }
  return props;
}

// The component type of the object literal a line sits inside: walk back to the
// nearest less-indented `Something {` opener.
function enclosingTypeName(lines, index) {
  const indent = lines[index].search(/\S/);
  for (let i = index - 1; i >= 0; i--) {
    const line = lines[i];
    const at = line.search(/\S/);
    if (at === -1) continue;
    if (at >= indent) continue;
    const m = line.match(/([A-Z][A-Za-z0-9_.]*)\s*\{\s*$/);
    if (m) return m[1].split(".").pop();
    return null;
  }
  return null;
}

{
  const failures = [];
  for (const file of allQml) {
    const text = fs.readFileSync(file, "utf8");
    const lines = text.split("\n");
    const ids = new Set();
    for (const m of text.matchAll(/^\s*id\s*:\s*([a-zA-Z_][\w]*)\s*$/gm)) ids.add(m[1]);

    lines.forEach((line, index) => {
      const m = line.match(/^\s*([a-z][A-Za-z0-9_]*)\s*:\s*([a-z][A-Za-z0-9_]*)\s*[,;]?\s*$/);
      if (!m) return;
      const [, lhs, rhs] = m;
      if (lhs !== rhs) return;
      if (!ids.has(lhs)) return;

      const typeName = enclosingTypeName(lines, index);
      if (!typeName) return;
      const target = byBasename.get(typeName + ".qml");
      if (!target) return;
      if (!declaredProperties(target).has(lhs)) return;

      failures.push(
        `${path.relative(shellRoot, file)}: in "${typeName} { ... }", "${lhs}: ${rhs}" `
        + `binds ${typeName}'s own ${lhs} property to itself instead of the id`);
    });
  }
  assert.deepStrictEqual(failures, [],
    "property bindings that shadow a sibling id:\n  " + failures.join("\n  "));
}

// ── 2. Quickshell types must come with the Quickshell import ──
//
// A curated list of types that only exist in the Quickshell module. Using one
// without `import Quickshell` makes the whole component un-instantiable, and
// QML reports that only when the delegate is first created — long after the
// load check has passed.
const quickshellOnlyTypes = [
  "FrameAnimation",       // removed in Quickshell 0.3.x; listed as a trap
  "ShellRoot",
  "SystemClock",
  "ElapsedTimer",
  "IpcHandler",
  "ProcessContext",
  "QuickshellGlobal",
];
{
  const failures = [];
  for (const file of allQml) {
    const text = fs.readFileSync(file, "utf8");
    if (!/^import Quickshell(\s|$)/m.test(text) && !/^import Quickshell\./m.test(text)) continue;
    // `import Quickshell` present — still check for explicitly removed types.
    if (/\bFrameAnimation\s*\{/.test(text)) {
      failures.push(`${path.relative(shellRoot, file)}: uses FrameAnimation, which Quickshell 0.3.2 does not export`);
    }
  }
  for (const type of quickshellOnlyTypes) {
    if (type === "FrameAnimation") continue; // handled above
    for (const file of allQml) {
      const text = fs.readFileSync(file, "utf8");
      if (new RegExp(`\\b${type}\\s*\\{`).test(text)
        && !/^import Quickshell(\s|$)/m.test(text)) {
        failures.push(`${path.relative(shellRoot, file)}: uses ${type} without "import Quickshell"`);
      }
    }
  }
  assert.deepStrictEqual(failures, [],
    "Quickshell types used without their module:\n  " + failures.join("\n  "));
}

// ── 3. A component must not measure itself from an anchored child ──
//
// `implicitHeight: someChild.height` where `someChild` is `anchors.fill: parent`
// (directly or through a wrapper Rectangle) is a circular binding: the parent's
// height comes from implicitHeight, the child's height comes from the parent.
const measured = /^\s*implicit(Height|Width)\s*:\s*([a-zA-Z_][\w.]*)\.(height|width)\s*\+/m;
{
  const failures = [];
  for (const file of allQml) {
    const text = fs.readFileSync(file, "utf8");
    const m = text.match(measured);
    if (!m) continue;
    const childName = m[2].split(".").pop();
    // Find an object with that id and check whether it fills its parent.
    const anchorFilled = new RegExp(`id:\\s*${childName}\\b[\\s\\S]{0,400}?anchors\\.fill\\s*:\\s*parent`);
    if (anchorFilled.test(text)) {
      failures.push(
        `${path.relative(shellRoot, file)}: implicit${m[1]} reads ${m[2]}.${m[3]}, `
        + `but "${childName}" is anchors.fill: parent — circular`);
    }
  }
  assert.deepStrictEqual(failures, [],
    "self-referential measurement:\n  " + failures.join("\n  "));
}

console.log(`ok - qml wiring (${allQml.length} files scanned)`);