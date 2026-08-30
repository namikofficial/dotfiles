.pragma library

function applyBase(model, snapshot, provider) {
    if (!snapshot || snapshot.provider !== provider || typeof snapshot.status !== "string"
            || !snapshot.data || typeof snapshot.data !== "object" || Array.isArray(snapshot.data)) return false;
    model.status = snapshot.status;
    model.data = snapshot.data;
    model.hasSynced = true;
    return true;
}

function numberOr(value, fallback) { return typeof value === "number" ? value : fallback; }
function stringOr(value, fallback) { return typeof value === "string" ? value : fallback; }
function nullableNumber(value) { return typeof value === "number" ? value : null; }
function nullableBool(value) { return typeof value === "boolean" ? value : null; }
