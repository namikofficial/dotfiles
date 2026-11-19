// Notifications must hide their content when screen-capture state is active
// or cannot be verified, and the rail indicator must use that same state.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const root = path.resolve(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");
const model = read("NotificationModel.qml");
const shell = read("shell.qml");
const indicator = read("bar/ScreenCaptureIndicator.qml");
const bar = read("bar/Bar.qml");
const pipewirePrivacy = fs.readFileSync(path.join(root, "PipewirePrivacy.js"), "utf8");
const privacyContext = {};
vm.runInNewContext(pipewirePrivacy.replace(/^\.pragma library\s*/, "")
  + "\nthis.detectScreenCapture = screenCaptureActive;", privacyContext);

assert(
  /readonly property bool privacyRedacted:\s*lockedRedacted\s*\|\|\s*!screenCaptureStatusKnown\s*\|\|\s*screenCaptureActive/.test(model),
  "notification details must stay hidden while locked, sharing, or capture status is unknown"
);
assert(
  /root\.screenCaptureStatusKnown\s*=\s*false/.test(model),
  "a failed or malformed PipeWire probe must remain an unknown privacy state"
);
assert(
  /lockedRedacted:\s*sessionSecurity\.privacyRedacted/.test(shell),
  "the lock-state privacy rule must remain connected to notification redaction"
);

const portalScreen = [{
  type: "PipeWire:Interface:Node",
  info: {
    state: "running",
    props: {
      "media.class": "Video/Source",
      "media.name": "xdpw-stream-MBBPOO",
      "node.name": "xdg-desktop-portal-wlr",
    },
  },
}];
assert.strictEqual(privacyContext.detectScreenCapture(JSON.stringify(portalScreen)), true,
  "an active portal screen stream without media.role must be detected");

const portalCamera = [{
  type: "PipeWire:Interface:Node",
  info: {
    state: "running",
    props: {
      "media.class": "Video/Source",
      "media.name": "xdpw-stream-camera",
      "media.role": "Camera",
      "node.name": "xdg-desktop-portal-hyprland",
    },
  },
}];
assert.strictEqual(privacyContext.detectScreenCapture(JSON.stringify(portalCamera)), false,
  "a portal camera source must not be mislabeled as screen sharing");
assert.throws(() => privacyContext.detectScreenCapture("invalid JSON"),
  "malformed PipeWire output must fail closed");
assert(
  /notificationModel\.screenCaptureActive/.test(indicator)
    && /notificationModel\.screenCaptureStatusKnown/.test(indicator)
    && /notificationModel:\s*root\.notificationModel/.test(bar),
  "the rail capture indicator and notification privacy must share one capture state"
);

console.log("notification privacy: sharing and unknown capture state redact content");
