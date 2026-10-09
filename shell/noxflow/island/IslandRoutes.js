// IslandRoutes.js — the island's one kind/panel table.
//
// NoxIsland.qml had two parallel switch statements — panelForIslandState() and
// labelForState() — plus a third implicit copy in the dashboard body. They
// drifted: the routes named a panel called "updater" that no component
// provides, and eight island kinds had no producer at all.
//
// One table, one place. A kind that is not listed here does not exist: it has
// no route, no label, no icon and no dashboard body.
//
// `trigger` is what the bar registered in MorphRegistry for the morph origin.
// `panel` is null for kinds the island shows without opening a panel.

.pragma library

var ROUTES = {
    "idle": {
        label: "NoxFlow",
        subLabel: "",
        icon: "",
        trigger: null,
        panel: null,
        section: "",
        dashboard: false
    },

    // ── Kinds produced by the bar's hover bridge ──
    "workspace": {
        label: "Workspaces",
        icon: "",
        trigger: "workspace",
        panel: "workspace",
        section: "",
        dashboard: true
    },
    "health": {
        label: "System Health",
        icon: "",
        trigger: "health",
        panel: "workspace",
        section: "health",
        dashboard: true
    },
    "connectivity": {
        label: "Connectivity",
        icon: "",
        trigger: "connectivity",
        panel: "workspace",
        section: "connectivity",
        dashboard: true
    },
    "provider-health": {
        label: "Provider Health",
        icon: "",
        trigger: "provider-health",
        panel: "workspace",
        section: "provider-health",
        dashboard: true
    },
    "audio-power": {
        label: "Audio & Power",
        icon: "",
        trigger: "audio-power",
        panel: "quick-settings",
        section: "audio",
        dashboard: true
    },
    "notification-preview": {
        label: "Notifications",
        icon: "",
        trigger: "notification-preview",
        panel: "notifications",
        section: "",
        dashboard: true
    },
    "updates": {
        label: "Updates",
        icon: "",
        trigger: "updates",
        // Sentinel, not a panel: handled by the island's launch-terminal path.
        panel: "update-terminal",
        section: "",
        dashboard: false
    },

    // ── Kinds produced by OSD activities ──
    "volume": {
        label: "Volume",
        icon: "",
        trigger: "volume",
        panel: "quick-settings",
        section: "audio",
        dashboard: false
    },
    "output-mute": {
        label: "Output Muted",
        icon: "",
        trigger: "volume",
        panel: "quick-settings",
        section: "audio",
        dashboard: false
    },
    "input-mute": {
        label: "Input Muted",
        icon: "",
        trigger: "mic",
        panel: "quick-settings",
        section: "audio",
        dashboard: false
    },
    "brightness": {
        label: "Brightness",
        icon: "",
        trigger: "brightness",
        panel: "quick-settings",
        section: "brightness",
        dashboard: false
    },
    "battery-warning": {
        label: "Battery",
        icon: "",
        trigger: "battery",
        panel: "quick-settings",
        section: "battery",
        dashboard: false
    },
    "timer": {
        label: "Timer",
        icon: "",
        trigger: null,
        panel: null,
        section: "",
        dashboard: false
    },
    "media": {
        label: "Now Playing",
        icon: "",
        trigger: "media",
        panel: "media",
        section: "",
        dashboard: false
    },
    "notification": {
        label: "Notification",
        icon: "",
        trigger: "notification-preview",
        panel: "notifications",
        section: "",
        dashboard: false
    }
};

function route(kind) {
    return ROUTES[kind] || ROUTES["idle"];
}

function exists(kind) {
    return Object.prototype.hasOwnProperty.call(ROUTES, kind);
}

function panel(kind) {
    var entry = route(kind);
    return entry.panel === undefined ? null : entry.panel;
}

function section(kind) {
    var entry = route(kind);
    return entry.section === undefined ? "" : entry.section;
}

function trigger(kind) {
    var entry = route(kind);
    return entry.trigger === undefined ? null : entry.trigger;
}

function label(kind) {
    var entry = route(kind);
    return entry.label === undefined ? "" : entry.label;
}

function icon(kind) {
    var entry = route(kind);
    return entry.icon === undefined ? "" : entry.icon;
}

function subLabel(kind) {
    var entry = route(kind);
    return entry.subLabel === undefined ? "" : entry.subLabel;
}

/// Kinds that open the island's dashboard body rather than a panel.
function dashboardKinds() {
    var out = [];
    for (var kind in ROUTES) if (ROUTES[kind].dashboard) out.push(kind);
    return out;
}

/// The sentinel panel name meaning "launch the update terminal", as opposed to
/// a panel the coordinator can open. Kept out of the coordinator's namespace so
/// a typo cannot be routed as a real panel.
var UPDATE_SENTINEL = "update-terminal";

function isUpdateSentinel(value) {
    return value === UPDATE_SENTINEL;
}