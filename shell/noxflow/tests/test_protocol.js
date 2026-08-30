const assert = require("assert");
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
console.log("noxflow QML protocol validation fixtures passed");
