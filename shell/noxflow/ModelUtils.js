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

/// Normalise a list field from a daemon snapshot to a plain JS array.
///
/// Why not `Array.isArray`: noxd snapshot payloads reach QML as QML sequence
/// objects, not native JS arrays. They report `constructor === Array` and a
/// correct `length`, but `Array.isArray()` returns **false**, so every
/// `Array.isArray(x) ? x : []` guard silently replaced live daemon data with an
/// empty list. That is why the workspace strip, the Wi-Fi list, the Bluetooth
/// device count, the power-profile list, media players, notification items and
/// transfer devices all rendered as permanently empty while the daemon
/// reported the providers as Available.
///
/// Accepts anything array-like and copies it, so the result is safe to mutate.
function asArray(value) {
    if (value === null || value === undefined) return [];
    if (Array.isArray(value)) return value;
    // QML sequence objects: array-like, iterable, but not Array.isArray.
    if (typeof value === "object" && typeof value.length === "number") {
        var out = [];
        for (var i = 0; i < value.length; i++) out.push(value[i]);
        return out;
    }
    return [];
}
