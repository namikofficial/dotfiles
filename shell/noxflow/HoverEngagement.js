// HoverEngagement.js — pure transition/generation logic for the NoxFlow
// dynamic island hover-and-pin state machine.
//
// The QML side wires user input into this module; it owns no QObjects, no
// timers, and no DOM. Every helper returns a new state object so callers can
// keep a single immutable snapshot and QML's binding system stays happy.
//
// Lifecycle of an engagement:
//   1. The user hovers a source chip. The chip calls `recordSourceHover(state,
//      "health", true)` and the island adopts that source kind.
//   2. The user moves the pointer from the chip into the island body. The
//      source releases (`recordSourceHover(state, "health", false)`) and the
//      island claims hover (`recordIslandHover(state, true)`). The engagement
//      must survive the transit, so the caller arms a generation-guarded
//      timer via `armTransit()`.
//   3. If both leaves become false before the grace expires, the timer fires
//      `commit()` which releases the engagement only when the captured
//      generation still matches — a stale callback for an already-replaced
//      engagement becomes a no-op.
//   4. Clicking the island while engaged pins the context; the timer is
//      canceled and the pin survives until the user unpins (re-click,
//      Escape, another context, click-away, or major panel close).
//   5. Routine OSD (volume, brightness, mic mute, …) is transient and never
//      disturbs a pin. Critical exclusive interrupts (battery-warning,
//      network-warning, …) temporarily replace a pin and remember it so it
//      can be restored on exit.
//
// State shape (all fields are plain JSON; the module never mutates input):
//   {
//     generation: int,                 // bumped on every replace transition
//     sourceHover: { [kind]: bool },    // which source chips claim hover
//     islandHovered: bool,              // island body pointer state
//     pin: { active: bool, kind: string, generation: int,
//            remembered: { active, kind } | null }, // remembered = critical override
//     osd: { active: bool, kind: string, generation: int },
//     critical: { active: bool, kind: string, generation: int,
//                 restoredPin: { active, kind } | null }
//   }

// Intentionally no `.pragma library` directive so this file can also be
// loaded directly by node-based tests (SystemSnapshot.js and
// WorkspacePresentation.js follow the same convention).

var TRANSIT_GRACE_MS = 900;
var DEFAULT_OSD_TIMEOUT_MS = 2000;

var SOURCE_KINDS = [
    "workspace",
    "health",
    "connectivity",
    "audio-power",
    "notification-preview",
    "updates",
    "sync",
    "provider-health"
];

// "Critical" engagements are exclusive interrupts (battery warnings, network
// warnings, recording, timers). They may temporarily replace a pin and must
// remember the prior pin so it can be restored on release.
var CRITICAL_KINDS = [
    "battery-warning",
    "network-warning",
    "recording",
    "timer"
];

// "Activity" / OSD kinds are routine transients — volume slider, brightness
// nudges, mic mute toggles, file transfer, etc. They never replace a pin.
var OSD_KINDS = [
    "volume",
    "brightness",
    "output-mute",
    "input-mute",
    "media",
    "file-transfer",
    "ai-completion",
    "build-result",
    "notification"
];

function clone(value) {
    if (value === null || typeof value !== "object") return value;
    if (Array.isArray(value)) {
        var out = [];
        for (var i = 0; i < value.length; i++) out[i] = clone(value[i]);
        return out;
    }
    var copy = {};
    for (var key in value) if (Object.prototype.hasOwnProperty.call(value, key)) copy[key] = clone(value[key]);
    return copy;
}

function emptyPin() {
    return { active: false, kind: "", generation: 0, remembered: null };
}

function emptyCritical() {
    return { active: false, kind: "", generation: 0, restoredPin: null };
}

function emptyOsd() {
    return { active: false, kind: "", generation: 0 };
}

function newState() {
    var sourceHover = {};
    for (var i = 0; i < SOURCE_KINDS.length; i++) sourceHover[SOURCE_KINDS[i]] = false;
    return {
        generation: 0,
        sourceHover: sourceHover,
        islandHovered: false,
        pin: emptyPin(),
        osd: emptyOsd(),
        critical: emptyCritical()
    };
}

function recordSourceHover(state, source, hovered) {
    if (SOURCE_KINDS.indexOf(source) < 0) return state;
    var next = clone(state);
    var wasHovered = next.sourceHover[source] === true;
    var wantHovered = !!hovered;
    if (wasHovered === wantHovered) return next;
    next.sourceHover[source] = wantHovered;
    // Any source-hover transition invalidates outstanding transit timers
    // armed against the prior hover set. Callers don't have to remember to
    // bump the generation themselves.
    next.generation = state.generation + 1;
    return next;
}

function clearSourceHover(state) {
    var next = clone(state);
    var any = false;
    for (var i = 0; i < SOURCE_KINDS.length; i++) if (next.sourceHover[SOURCE_KINDS[i]]) { any = true; break; }
    if (!any) return next;
    for (var j = 0; j < SOURCE_KINDS.length; j++) next.sourceHover[SOURCE_KINDS[j]] = false;
    next.generation = state.generation + 1;
    return next;
}

function recordIslandHover(state, hovered) {
    var next = clone(state);
    var wantHovered = !!hovered;
    if (next.islandHovered === wantHovered) return next;
    next.islandHovered = wantHovered;
    // Island hover is a passive flag the caller reads to decide whether to
    // arm or cancel a transit timer. It does not invalidate pending timers;
    // those are bumped by source-hover transitions and pin/critical toggles.
    return next;
}

function isAnySourceHovered(state) {
    for (var i = 0; i < SOURCE_KINDS.length; i++) if (state.sourceHover[SOURCE_KINDS[i]]) return true;
    return false;
}

function isAnyHovered(state) {
    return state.islandHovered || isAnySourceHovered(state);
}

function hoveredSourceKind(state) {
    for (var i = 0; i < SOURCE_KINDS.length; i++) if (state.sourceHover[SOURCE_KINDS[i]]) return SOURCE_KINDS[i];
    return "";
}

// armTransit stamps the current generation into a token the caller passes to
// a QML Timer. When the timer fires it must compare token.generation against
// state.generation before mutating anything — that makes stale callbacks a
// safe no-op when the engagement has already been replaced.
function armTransit(state, now, graceMs) {
    return {
        generation: state.generation,
        deadline: (typeof now === "number" ? now : 0) + (typeof graceMs === "number" ? graceMs : TRANSIT_GRACE_MS)
    };
}

function tickTransit(state, token, now) {
    if (!token) return false;
    if (typeof token.generation !== "number") return false;
    if (token.generation !== state.generation) return false;
    if (typeof now !== "number") return false;
    return now >= token.deadline;
}

function bumpGeneration(state) {
    var next = clone(state);
    next.generation = state.generation + 1;
    return next;
}

// Resolve which kind (if any) should currently drive the island dashboard.
// Hover wins over OSD, but a pin or critical override always wins over hover.
function effectiveKind(state) {
    if (state.critical.active) return state.critical.kind;
    if (state.pin.active) return state.pin.kind;
    var hovered = hoveredSourceKind(state);
    if (hovered) return hovered;
    if (state.islandHovered && state.pin.active) return state.pin.kind;
    if (state.osd.active) return state.osd.kind;
    return "";
}

function isEngaged(state) {
    if (state.critical.active) return true;
    if (state.pin.active) return true;
    if (isAnyHovered(state)) return true;
    if (state.osd.active) return true;
    return false;
}

// Pin toggle: if the supplied kind matches the current pin, release; else
// replace with the supplied kind (and adopt its generation so any in-flight
// timer is invalidated).
function togglePin(state, kind) {
    if (!kind) return state;
    if (state.pin.active && state.pin.kind === kind) {
        var cleared = clone(state);
        cleared.pin = emptyPin();
        return bumpGeneration(cleared);
    }
    var replaced = clone(state);
    replaced.pin = {
        active: true,
        kind: kind,
        generation: state.generation + 1,
        remembered: null
    };
    return bumpGeneration(replaced);
}

function releasePin(state) {
    if (!state.pin.active) return state;
    var cleared = clone(state);
    cleared.pin = emptyPin();
    return bumpGeneration(cleared);
}

// A critical interrupt may temporarily replace a pin. We remember the prior
// pin so we can restore it on release.
function enterCritical(state, kind) {
    if (CRITICAL_KINDS.indexOf(kind) < 0) return state;
    var next = clone(state);
    var restoredPin = state.critical.active
        ? state.critical.restoredPin
        : state.pin.active ? { active: true, kind: state.pin.kind } : null;
    next.critical = {
        active: true,
        kind: kind,
        generation: state.generation + 1,
        restoredPin: restoredPin
    };
    next.pin = emptyPin();
    return bumpGeneration(next);
}

function exitCritical(state) {
    if (!state.critical.active) return state;
    var next = clone(state);
    var restored = next.critical.restoredPin;
    next.critical = emptyCritical();
    if (restored && restored.active) {
        next.pin = {
            active: true,
            kind: restored.kind,
            generation: state.generation + 1,
            remembered: null
        };
    }
    return bumpGeneration(next);
}

// Routine OSD never replaces a pin or critical interrupt. It only takes the
// island when nothing else is engaged.
function enterOsd(state, kind, timeoutMs) {
    var next = clone(state);
    next.osd = {
        active: true,
        kind: kind,
        generation: state.generation + 1,
        timeoutMs: typeof timeoutMs === "number" ? timeoutMs : DEFAULT_OSD_TIMEOUT_MS
    };
    return next;
}

function exitOsd(state) {
    if (!state.osd.active) return state;
    var next = clone(state);
    next.osd = emptyOsd();
    return next;
}

// Detect a click-away: the supplied point (in island-local coordinates) is
// outside the island body and outside all source chip regions.
function isClickAway(state, sourceBounds, islandBounds, point) {
    if (!point) return false;
    if (islandBounds && pointInRect(point, islandBounds)) return false;
    if (sourceBounds) {
        for (var i = 0; i < sourceBounds.length; i++) {
            if (pointInRect(point, sourceBounds[i])) return false;
        }
    }
    return true;
}

function pointInRect(point, rect) {
    if (!point || !rect) return false;
    var x = Number(point.x);
    var y = Number(point.y);
    if (!isFinite(x) || !isFinite(y)) return false;
    return x >= rect.x && x <= rect.x + rect.width
        && y >= rect.y && y <= rect.y + rect.height;
}

// Compact snapshot for tests/diagnostics.
function view(state) {
    return {
        generation: state.generation,
        islandHovered: state.islandHovered,
        sourceHover: clone(state.sourceHover),
        pin: clone(state.pin),
        osd: clone(state.osd),
        critical: clone(state.critical),
        effective: effectiveKind(state),
        engaged: isEngaged(state)
    };
}
