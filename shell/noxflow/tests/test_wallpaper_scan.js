const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");
const vm = require("vm");

const source = fs.readFileSync(require.resolve("../WallpaperScan.js"), "utf8")
  .replace(/^\.pragma library\s*/, "");
const context = { Array, String };
vm.createContext(context);
vm.runInContext(source, context);

assert.deepStrictEqual(Array.from(context.argumentsFor([])), []);
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "noxflow-wallpaper-"));
try {
  fs.writeFileSync(path.join(tempDir, "clear sky.png"), "");
  fs.writeFileSync(path.join(tempDir, "night\nview.webp"), "");
  fs.writeFileSync(path.join(tempDir, "anime-girl.jpg"), "");
  fs.writeFileSync(path.join(tempDir, "notes.txt"), "");

  const argv = context.argumentsFor([tempDir, tempDir]);
  assert.strictEqual(argv[0], "find");
  assert.strictEqual(argv[1], "--");
  assert(argv.includes("-print0"));
  assert(!argv.includes("-E"));
  assert.strictEqual(argv.filter((value) => value === tempDir).length, 1);

  const run = spawnSync(argv[0], argv.slice(1), { encoding: "buffer" });
  assert.strictEqual(run.status, 0, run.stderr.toString());
  const parsed = context.result(run.status, run.stdout.toString());
  assert.strictEqual(parsed.error, "");
  assert.deepStrictEqual(Array.from(parsed.walls, (wall) => wall.name), ["clear sky.png", "night\nview.webp"]);

  assert.deepStrictEqual(Array.from(context.result(0, "").walls), []);
  assert.strictEqual(context.result(0, "").error, "");
  assert.strictEqual(context.result(1, "").error, "wallpaper scan failed");
} finally {
  fs.rmSync(tempDir, { recursive: true, force: true });
}

console.log("noxflow wallpaper scan fixtures passed");
