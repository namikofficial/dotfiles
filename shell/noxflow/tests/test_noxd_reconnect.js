const assert = require("assert");
const fs = require("fs");

const clientQml = fs.readFileSync(require.resolve("../NoxdClient.qml"), "utf8");

assert(/function disconnectSocketDeferred\(\)[\s\S]*?Qt\.callLater\(/.test(clientQml),
  "NoxdClient must defer socket teardown with Qt.callLater");

const errorHandler = /function handleSocketError\([^)]*\)\s*\{[\s\S]*?\n    \}/.exec(clientQml);
assert(errorHandler, "NoxdClient must define handleSocketError()");
assert(errorHandler[0].includes("disconnectSocketDeferred()"),
  "handleSocketError must call disconnectSocketDeferred()");
assert(!/socket\.connected\s*=\s*false/.test(errorHandler[0]),
  "handleSocketError must not mutate socket.connected = false synchronously inside onError");

console.log("ok - noxd socket deferred teardown regression fixtures passed");
