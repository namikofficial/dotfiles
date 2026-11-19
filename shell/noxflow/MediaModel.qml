import QtQml
import "ModelUtils.js" as Utils

ProviderModel {
    providerName: "media"
    property var players: []
    property string activePlayer: ""
    property string identity: ""
    property string playbackStatus: "unknown"
    property string title: ""
    property var artists: []
    property string album: ""
    property string artwork: ""
    property var position: null
    property var duration: null
    property var volume: null
    property var shuffle: null
    property string repeat: ""
    property bool canSeek: false
    property bool canControl: false
    property double positionUpdatedAt: 0
    property double positionReceivedAtMs: 0
    property var active: null

    function normalizeMediaUrl(pathOrUrl) {
        var raw = Utils.stringOr(pathOrUrl, "").trim();
        if (raw === "") return "";
        if (raw.charAt(0) === "/") return "file://" + raw;
        return raw;
    }

    function normalizeArtists(artistsValue, artistValue) {
        var raw = Utils.asArray(artistsValue);
        if (raw.length === 0) {
            var fromArtist = Utils.asArray(artistValue);
            if (fromArtist.length > 0) raw = fromArtist;
            else if (typeof artistValue === "string" && artistValue.trim() !== "") raw = [artistValue];
        }
        var out = [];
        for (var i = 0; i < raw.length; i++) {
            var entry = raw[i] !== undefined && raw[i] !== null ? String(raw[i]).trim() : "";
            if (entry !== "") out.push(entry);
        }
        return out;
    }

    function applySnapshot(snapshot) {
        if (!Utils.applyBase(this, snapshot, providerName)) return false;
        var next = snapshot.data;
        players = Utils.asArray(next.players);
        activePlayer = Utils.stringOr(next.active_player, "");
        active = next.active === undefined ? null : next.active;
        var current = active && typeof active === "object" ? active : {};
        identity = Utils.stringOr(current.identity, "");
        playbackStatus = Utils.stringOr(current.playback_status, "unknown");
        title = Utils.stringOr(current.title, "");
        artists = normalizeArtists(current.artists, current.artist);
        album = Utils.stringOr(current.album, "");
        var cachedArt = normalizeMediaUrl(Utils.stringOr(current.artwork_cache, ""));
        var directArt = normalizeMediaUrl(Utils.stringOr(current.artwork_url, ""));
        artwork = cachedArt !== "" ? cachedArt : directArt;
        position = Utils.nullableNumber(current.position);
        duration = Utils.nullableNumber(current.duration);
        volume = Utils.nullableNumber(current.volume);
        shuffle = Utils.nullableBool(current.shuffle);
        repeat = Utils.stringOr(current.repeat, "");
        canSeek = current.can_seek === true;
        canControl = current.can_control === true;
        positionUpdatedAt = Number(current.position_updated_at) || 0;
        positionReceivedAtMs = position !== null ? Date.now() : 0;
        return true;
    }
}
