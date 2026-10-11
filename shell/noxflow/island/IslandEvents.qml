import QtQuick
import "../ModelUtils.js" as Utils

// IslandEvents.qml — daemon events and model signals become island activities.
//
// Extracted from IslandHost.qml. The host owned both the raw
// `noxd.onEventReceived` fan-out and the AudioModel/BrightnessModel change
// handlers, which meant two producers per OSD dimension and a guard delta that
// was satisfied by whichever path won a race.
//
// One producer per dimension, all of them here:
//
//   volume / brightness / output-mute / input-mute   model change signals
//   media                                          daemon media events
//   battery-warning                                daemon power events
//
// The `notifications` event branch that used to sit here was removed: noxd has
// no notifications provider (EventBus::subscribe does not validate names), so
// that branch could never fire.



// The three handler blocks are grouped under an explicit Item-free parent:
// a QtObject has no default property, so they must sit inside a container
// that does (QtObject children need an explicit parent to be valid).

Item {
    id: root

    // ── Inputs ──
    property var noxd: null
    property var audio: null
    property var brightness: null
    property var media: null

    /// Called with an activity descriptor. The host owns the queue.
    property var enqueue: null
    property var deactivate: null

    // ── Suppression ──
    // OSDs are suppressed until the models have synced, otherwise the first
    // snapshot after startup shows a burst of volume/brightness cards for
    // values the user never changed.
    property bool suppressStartupEvents: true
    property real guardVolume: -1
    property real guardBrightness: -1
    property bool guardsSeeded: false

    /// Adopt the models' current values as the baseline, so the first change
    /// the user makes is the first OSD. Each guard is seeded independently and
    /// only while it is still unset: the old version latched `guardsSeeded`
    /// as soon as both models reported `hasSynced`, which happens before their
    /// snapshot values land, so both guards froze at 0 and the guard stopped
    /// meaning anything.
    function seedGuards() {
        if (root.audio && root.audio.hasSynced && root.guardVolume < 0)
            root.guardVolume = root.audio.outputVolume;
        if (root.brightness && root.brightness.hasSynced && root.guardBrightness < 0)
            root.guardBrightness = root.brightness.percentage;
        root.guardsSeeded = root.guardVolume >= 0 && root.guardBrightness >= 0;
    }

    // ── Media state (read by the host) ──
    property string mediaTitle: ""
    property string mediaArtist: ""
    property string mediaArtwork: ""
    property string mediaStatus: ""
    property bool mediaAvailable: false

    readonly property int priMedia: 5
    readonly property int priBattery: 8
    readonly property int priVolume: 3
    readonly property int priBrightness: 3
    readonly property int priOutputMute: 4
    readonly property int priInputMute: 4

    function submit(kind, label, icon, value, maximum, priority, timeout) {
        if (root.enqueue) root.enqueue(kind, label, icon, value, maximum, priority, timeout);
    }

    // ── Daemon events ──
    Connections {
        target: root.noxd
        function onEventReceived(e) {
            if (!e || !e.provider) return;
            if (e.provider === "audio" || e.provider === "brightness") {
                // Volume and brightness OSDs come from the model change
                // signals below, and only from them. This branch used to
                // "just maintain the guard" for the daemon event, but noxd
                // delivers the event and the model snapshot from the same
                // publish, so the event always landed first: it set the guard
                // to the new value, and the model handler then bailed out on
                // its own `abs(new - guard) <= 1` test. The volume and
                // brightness OSDs were dead on every change, panel open or
                // not. The old `e.data` condition also let an audio event with
                // no payload fall through to the media and power branches.
                return;
            }
            if (e.provider === "media") {
                var md = e.data || {};
                if (md.playback_status === "playing" || md.title) {
                    root.mediaTitle = md.title || "";
                    var artistList = md.artists ? Utils.asArray(md.artists) : [];
                    root.mediaArtist = artistList.length > 0
                        ? artistList.join(", ")
                        : (md.artists ? String(md.artists) : "");
                    root.mediaArtwork = md.artwork_url || md.artwork_cache || "";
                    root.mediaStatus = md.playback_status || "";
                    root.mediaAvailable = true;
                    root.submit("media", root.mediaTitle, "", 50, 100, root.priMedia, 5000);
                } else {
                    root.mediaAvailable = false;
                }
                return;
            }
            if (e.provider === "power") {
                var pd = e.data || {};
                if (pd.warning === "low_battery" || pd.warning === "critical_battery")
                    root.submit("battery-warning",
                                "Battery: " + Math.round(pd.percentage || 0) + "%",
                                "", 1, 1, root.priBattery, 8000);
                return;
            }
        }
    }

    // ── Audio: one producer for volume and both mutes ──
    Connections {
        target: root.audio
        function onOutputVolumeChanged() {
            if (!root.audio || !root.audio.hasSynced) return;
            // While startup suppression is on, track the guard instead of
            // emitting: lifting suppression then cannot produce a burst of
            // cards for values nobody changed.
            if (root.suppressStartupEvents) { root.guardVolume = root.audio.outputVolume; return }
            if (root.guardVolume < 0) { root.guardVolume = root.audio.outputVolume; return }
            if (Math.abs(root.audio.outputVolume - root.guardVolume) <= 1) return;
            root.guardVolume = root.audio.outputVolume;
            // Pipewire's volume range is not always 0-100; a hardcoded 100 made
            // the OSD bar overflow on any system whose max differs.
            var max = root.audio.maxVolume > 0 ? root.audio.maxVolume : 100;
            root.submit("volume", "Volume", "", root.audio.outputVolume, max, root.priVolume, 2000);
        }
        function onOutputMutedChanged() {
            if (root.suppressStartupEvents || !root.audio || !root.audio.hasSynced) return;
            var max = root.audio.maxVolume > 0 ? root.audio.maxVolume : 100;
            root.submit("output-mute",
                        root.audio.outputMuted ? "Muted" : "Unmuted",
                        root.audio.outputMuted ? "" : "",
                        root.audio.outputVolume || 0, max, root.priOutputMute, 2000);
        }
        function onInputMutedChanged() {
            if (root.suppressStartupEvents || !root.audio || !root.audio.hasSynced) return;
            root.submit("input-mute",
                        root.audio.inputMuted ? "Mic Muted" : "Mic Live",
                        "", 0, 1, root.priInputMute, 2000);
        }
        function onHasSyncedChanged() { root.seedGuards(); }
    }

    Connections {
        target: root.brightness
        function onPercentageChanged() {
            if (!root.brightness || !root.brightness.hasSynced) return;
            if (root.suppressStartupEvents) { root.guardBrightness = root.brightness.percentage; return }
            if (root.guardBrightness < 0) { root.guardBrightness = root.brightness.percentage; return }
            if (Math.abs(root.brightness.percentage - root.guardBrightness) <= 1) return;
            root.guardBrightness = root.brightness.percentage;
            root.submit("brightness", "Brightness", "",
                        root.brightness.percentage, 100, root.priBrightness, 2000);
        }
        function onHasSyncedChanged() { root.seedGuards(); }
    }
}
