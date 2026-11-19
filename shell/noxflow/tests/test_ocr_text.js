const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

const source = fs.readFileSync(require.resolve("../surfaces/capture/OcrText.js"), "utf8")
  .replace(/^\.pragma library\s*/, "");
const context = { String };
vm.createContext(context);
vm.runInContext(source, context);

assert.strictEqual(context.validLanguage("eng"), "eng");
assert.strictEqual(context.validLanguage("eng+fra"), "eng+fra");
assert.strictEqual(context.validLanguage("eng;reboot"), "");
assert.strictEqual(context.validLanguage("-l eng"), "");
assert.strictEqual(context.normalize("  one   line  \r\nsecond\t\n\n next  ", false, false), "one line second\n\nnext");
assert.strictEqual(context.normalize("one   line\nsecond\n\nnext", false, true), "one line second next");
assert.strictEqual(context.normalize(" one  \n two\t\n", true, false), "one\n two");
assert.strictEqual(context.normalize("\n \n", false, false), "");

console.log("noxflow OCR text fixtures passed");
