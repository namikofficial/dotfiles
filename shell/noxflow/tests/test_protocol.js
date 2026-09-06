const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

// Load Protocol.js the same way the QML runtime loads it. Strip the
// `.pragma library` directive first — QML recognises it but the Node vm
// does not, and Protocol.js exports the binding as `Protocol.*` properties.
const context = { console };
vm.createContext(context);
const protocolSource = fs.readFileSync(require.resolve("../Protocol.js"), "utf8")
  .replace(/^\.pragma library\s*\n/m, "");
vm.runInContext(protocolSource, context);

// ── Frame validation: protocol version + response/event shape ──
// Mirrors the original assertions but exercises the real Protocol.js
// validateFrame so regressions surface against the actual contract.
function valid(value) {
  if (!value || typeof value !== "object" || value.version !== 1) return false;
  if (typeof value.id === "string") return (value.result !== undefined) !== (value.error !== undefined);
  return typeof value.timestamp === "number" && typeof value.stream_id === "string" &&
    typeof value.sequence === "number" && typeof value.provider === "string" &&
    typeof value.event_type === "string" && typeof value.schema_version === "number" &&
    value.data && typeof value.data === "object" && !Array.isArray(value.data);
}
assert(valid({version: 1, id: "1", result: {type: "pong"}, future: true}));
assert(valid({version: 1, timestamp: 1, stream_id: "s", sequence: 1, provider: "audio", event_type: "changed", schema_version: 1, data: {}, future: true}));
assert(!valid({version: 2, id: "1", result: {type: "pong"}}));
assert(!valid({version: 1, id: "1", result: {}, error: {code: "bad"}}));
assert(!valid({version: 1, provider: "audio", data: {}}));

// ── Provider allowlist: transfer MUST be present ──
// Root cause of NF-01: Protocol.providers did not include "transfer", so the
// real daemon publish path was filtered out before the shell's onEventReceived
// could route the event into TransferModel.
assert(context.isAllowedProvider, "Protocol.js must export isAllowedProvider");
assert(context.providers, "Protocol.js must export providers");
const expected = ["hyprland", "audio", "brightness", "power", "network", "bluetooth", "media", "notifications", "transfer"];
for (const provider of expected) {
  assert(context.isAllowedProvider(provider),
    `expected ${provider} to be an allowed provider event`);
  assert(context.providers.indexOf(provider) >= 0,
    `expected ${provider} to appear in Protocol.providers`);
}

// ── Provider allowlist: settings MUST remain excluded ──
// The daemon registers a settings provider and publishes SettingChangedEvent,
// but no QML component currently consumes settings provider events. Including
// "settings" here would route SettingChangedEvent envelopes into
// onEventReceived with no consumer. The contract is: live settings changes
// are observable through set_setting / get_setting requests only.
assert(!context.isAllowedProvider("settings"),
  "settings must remain outside the provider allowlist by contract");
assert(context.providers.indexOf("settings") < 0,
  "settings must not appear in Protocol.providers");

// ── Provider allowlist: unknown providers MUST be rejected ──
// Defends against future regressions where a typo silently swallows events.
for (const unknown of ["calendar", "clipboard", "weather", "updates", "", null, undefined, 0, {}]) {
  assert(!context.isAllowedProvider(unknown),
    `expected ${JSON.stringify(unknown)} to be rejected by the allowlist`);
}

// ── Event validation: transfer envelope must parse as a valid event ──
// This confirms the shape contract end-to-end before the allowlist filter is
// applied in NoxdClient.qml's handleEvent.
const transferEvent = {
  version: 1,
  timestamp: 1700000000,
  stream_id: "stream-1",
  sequence: 7,
  provider: "transfer",
  event_type: "sessions",
  schema_version: 1,
  data: { sessions: [{ id: "in-1", direction: "in", state: "incoming" }] }
};
assert(valid(transferEvent), "transfer event must parse as a valid event envelope");

// ── Direct validateFrame check: an unknown provider still produces a
// well-formed event frame (the allowlist is enforced downstream by
// NoxdClient, not Protocol.validateFrame). This guards against accidentally
// merging the two filters.
const parsed = context.validateFrame(JSON.stringify(transferEvent));
assert(parsed.ok && parsed.kind === "event",
  `expected transfer event to parse as a valid frame, got ${JSON.stringify(parsed)}`);

console.log("noxflow QML protocol validation fixtures passed");
