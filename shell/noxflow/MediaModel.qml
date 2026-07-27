import QtQml
import "ModelUtils.js" as Utils

ProviderModel {
    providerName: "media"
    property var players: []
    property string activePlayer: ""
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
    property var active: null

    function applySnapshot(snapshot) {
        if (!Utils.applyBase(this, snapshot, providerName)) return false;
        var next = snapshot.data;
        players = Array.isArray(next.players) ? next.players : [];
        activePlayer = Utils.stringOr(next.active_player, "");
        active = next.active === undefined ? null : next.active;
        var current = active && typeof active === "object" ? active : {};
        playbackStatus = Utils.stringOr(current.playback_status, "unknown");
        title = Utils.stringOr(current.title, "");
        artists = Array.isArray(current.artists) ? current.artists : (current.artist ? [current.artist] : []);
        album = Utils.stringOr(current.album, "");
        artwork = Utils.stringOr(current.artwork_url, Utils.stringOr(current.artwork_cache, ""));
        position = Utils.nullableNumber(current.position);
        duration = Utils.nullableNumber(current.duration);
        volume = Utils.nullableNumber(current.volume);
        shuffle = Utils.nullableBool(current.shuffle);
        repeat = Utils.stringOr(current.repeat, "");
        return true;
    }
}
