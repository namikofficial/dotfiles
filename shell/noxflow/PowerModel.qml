import QtQml
import "ModelUtils.js" as Utils

// PowerModel — derived state from the `power` noxd provider.
//
// The provider reports three independent slices:
//   • battery  (always present when UPower is available)
//   • ac       (always present when UPower is available)
//   • profiles (only present when power-profiles-daemon is reachable)
//
// Profiles are derived strictly from the snapshot. If the daemon is missing,
// the field stays empty; the model never fabricates a default profile name
// and never triggers a profile change itself. Callers (e.g. ControlCentre)
// already gate writes on `root.noxd.connected` and on profile availability.
//
// `status` mirrors the provider's `ProviderStatus`:
//   "pending"     no snapshot received yet
//   "available"   UPower responded successfully
//   "degraded"    snapshot succeeded but profile daemon is missing
//   "unavailable" the last attempt failed
ProviderModel {
    id: powerRoot
    providerName: "power"

    // ── Battery (UPower) ──
    property bool batteryPresent: false
    property var percentage: null
    property string chargingState: "unknown"
    property var acOnline: null
    property var timeToEmptySeconds: null
    property var timeToFullSeconds: null
    property var healthPercentage: null
    property string warningLevel: "unknown"
    property bool critical: false

    // ── Power profiles ──
    // `activeProfile` is the empty string when no daemon is reachable;
    // `profilesAvailable` makes that distinction explicit so the UI can
    // hide the profile row entirely instead of showing a fabricated value.
    property string activeProfile: ""
    property var availableProfiles: []
    property bool profilesAvailable: false
    // The driver reported by power-profiles-daemon for the active profile
    // (e.g. "platform_profile", "intel_pstate", "amd_pstate"). Empty string
    // means no driver info — never fabricated.
    property string activeProfileDriver: ""
    // True when the last snapshot for the profile slice was authoritative.
    // Mirrors `profilesAvailable` from the daemon.
    property bool profileDataAvailable: false

    // ── Freshness (derived from the ProviderModel base + a real clock) ──
    readonly property int staleAfterMs: 6000
    property real lastUpdateMs: 0
    property real ageMs: 0
    property bool stale: false
    // Lifecycle status derived purely from real snapshot data:
    //   "pending"     no snapshot ever
    //   "live"        snapshot recent (< staleAfterMs)
    //   "stale"       snapshot older than threshold
    //   "unavailable" the last attempt failed (ProviderModel.status === "unavailable")
    readonly property string freshness: !hasSynced
        ? "pending"
        : status === "unavailable"
            ? "unavailable"
            : (lastUpdateMs > 0 && ageMs > staleAfterMs) ? "stale" : "live"

    property Timer freshnessTimer: Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            var now = Date.now();
            powerRoot.ageMs = powerRoot.lastUpdateMs > 0 ? now - powerRoot.lastUpdateMs : 0;
            powerRoot.stale = powerRoot.lastUpdateMs > 0 && powerRoot.ageMs > powerRoot.staleAfterMs;
        }
    }

    function applySnapshot(snapshot) {
        if (!Utils.applyBase(this, snapshot, providerName)) return false;
        var next = snapshot.data;

        // Battery slice.
        batteryPresent = next.battery_present === true;
        percentage = Utils.nullableNumber(next.percentage);
        chargingState = Utils.stringOr(next.charging_state, "unknown");
        acOnline = Utils.nullableBool(next.ac_online);
        timeToEmptySeconds = Utils.nullableNumber(next.time_to_empty_seconds);
        timeToFullSeconds = Utils.nullableNumber(next.time_to_full_seconds);
        healthPercentage = Utils.nullableNumber(next.health_percentage);
        warningLevel = Utils.stringOr(next.warning_level, "unknown");
        critical = next.critical === true;

        // Profile slice. Profiles are sourced from power-profiles-daemon
        // when present; the daemon's own field `profiles_available` is the
        // single source of truth. We never fabricate profile names.
        profilesAvailable = next.profiles_available === true;
        profileDataAvailable = profilesAvailable && Array.isArray(next.available_profiles);
        availableProfiles = profileDataAvailable ? next.available_profiles : [];
        activeProfile = profilesAvailable
            ? Utils.stringOr(next.active_profile, "")
            : "";
        // Driver metadata for the active profile is optional and only set
        // when the daemon returned profiles. `slice(0)` is defensive — the
        // daemon serializes it as a string per profile entry.
        if (profileDataAvailable) {
            var driver = "";
            for (var i = 0; i < availableProfiles.length; i++) {
                var entry = availableProfiles[i];
                if (entry && entry.name === activeProfile) {
                    driver = typeof entry.driver === "string" ? entry.driver : "";
                    break;
                }
            }
            activeProfileDriver = driver;
        } else {
            activeProfileDriver = "";
        }

        lastUpdateMs = Date.now();
        ageMs = 0;
        stale = false;
        return true;
    }
}