.pragma library

// SnapshotMerge — how a provider snapshot combines with the cached one.
//
// Extracted from NoxdClient.publishSnapshots so it can be unit-tested. That
// logic decides what the UI actually shows, and the bug it had was silent: a
// subscription snapshot was merged into the previous state instead of
// replacing it, so any key the provider had *dropped* was resurrected from the
// cache and stayed in the UI forever. An SSID that disconnected came back; a
// list a provider had emptied stayed populated. Nothing errored, and no status
// disagreed — the models simply received data that was no longer true.

/**
 * Whether a snapshot is the provider's complete state (a `get_state` or
 * `subscribe` reply) or a partial update (an event envelope).
 */
function isFullSnapshot(snapshot) {
    if (!snapshot || typeof snapshot !== "object") return false;
    if (snapshot.status === undefined) return false;
    return snapshot.data !== undefined && snapshot.data !== null && typeof snapshot.data === "object";
}

/**
 * Merge an event's data into the provider's cached data.
 *
 * Only used for events, which carry a partial update. Keys absent from the
 * incoming data are carried over from the cache, because an event is not a
 * statement about the whole provider.
 */
function mergeEventData(previousData, incomingData) {
    var merged = {};
    if (previousData) {
        for (var key in previousData) merged[key] = previousData[key];
    }
    if (incomingData) {
        for (var key in incomingData) merged[key] = incomingData[key];
    }
    return merged;
}

/**
 * Combine a cached provider state with an incoming snapshot.
 *
 * @param previous   the cached {provider, status, data}, or undefined
 * @param snapshot   the incoming {provider, status, data}
 * @param isComplete true for get_state / subscribe replies, false for events
 *
 * A complete snapshot replaces. A partial update merges, and only when both
 * sides are healthy — folding a delta into a provider that has already failed
 * would paper over the failure with stale-but-plausible data.
 */
function apply(previous, snapshot, isComplete) {
    if (!isFullSnapshot(snapshot)) return snapshot;
    if (isComplete || !previous || !isFullSnapshot(previous)) return snapshot;
    if (previous.status !== "available" || snapshot.status !== "available") return snapshot;
    return {
        provider: snapshot.provider,
        status: snapshot.status,
        data: mergeEventData(previous.data, snapshot.data)
    };
}

/**
 * The status to report for a provider after an event arrived.
 *
 * EventEnvelope has no status field, so an event says nothing about health.
 * Asserting "available" here flipped a provider that the daemon had marked
 * error back to green on every event it emitted. A provider we have never
 * heard of counts as available, since receiving data from it is that evidence.
 */
function statusAfterEvent(cached, snapshot) {
    if (cached && cached.status) return cached.status;
    return (snapshot && snapshot.status) || "available";
}