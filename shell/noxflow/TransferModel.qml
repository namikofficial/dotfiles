import QtQml
import "ModelUtils.js" as Utils

// TransferModel — Quick Share state from the noxd 'transfer' provider.
// Mirrors devices + transfer sessions published by the daemon (LocalSend v2).
ProviderModel {
    id: root
    providerName: "transfer"
    // Set by shell.qml: the noxd client used for actions.
    property var noxd: null

    property var devices: []
    property var sessions: []
    readonly property var incoming: sessions.filter(function(s) { return s.direction === "in"; })
    readonly property var outgoing: sessions.filter(function(s) { return s.direction === "out"; })
    readonly property var pendingIncoming: incoming.filter(function(s) { return s.state === "incoming" || s.state === "offered"; })
    readonly property var activeTransfers: sessions.filter(function(s) { return s.state === "transferring"; })
    readonly property var activeIncoming: incoming.filter(function(s) { return s.state === "incoming" || s.state === "offered" || s.state === "transferring"; })
    readonly property var activeOutgoing: outgoing.filter(function(s) { return s.state === "transferring"; })
    readonly property int incomingCount: pendingIncoming.length
    readonly property bool hasActiveTransfers: activeTransfers.length > 0 || pendingIncoming.length > 0
    // True while the Quick Share panel is open (drives the refresh timer).
    property bool refreshing: false

    function applySnapshot(snapshot) {
        if (!Utils.applyBase(this, snapshot, providerName)) return false;
        var next = snapshot.data;
        devices = Array.isArray(next.devices) ? next.devices : [];
        sessions = Array.isArray(next.sessions) ? next.sessions : [];
        return true;
    }

    // Handle a daemon event (discovery/sessions). Updates the lists and emits
    // a notification for new incoming requests.
    function applyEvent(event) {
        if (!event || event.provider !== providerName) return false;
        if (event.event_type === "discovery" && event.data && Array.isArray(event.data.devices)) {
            devices = event.data.devices;
            return true;
        }
        if (event.event_type === "sessions" && event.data) {
            if (Array.isArray(event.data.sessions)) {
                sessions = event.data.sessions;
            }
            // Surface new incoming requests; prune notified ids for sessions
            // that are no longer pending.
            if (event.data.sessions) {
                var ids = {};
                for (var i = 0; i < event.data.sessions.length; i++) {
                    var s = event.data.sessions[i];
                    ids[s.id] = true;
                    if (s.direction === "in" && (s.state === "incoming" || s.state === "offered")) {
                        if (!_notifiedIds[s.id]) {
                            _notifiedIds[s.id] = true;
                            incomingRequested(s);
                        }
                    }
                }
                for (var key in _notifiedIds) {
                    if (!ids[key]) delete _notifiedIds[key];
                }
            }
            return true;
        }
        return false;
    }

    signal incomingRequested(var session)
    property var _notifiedIds: ({})

    // ── Actions ──
    function discover() { if (root.noxd) root.noxd.runAction({ transfer_discover: {} }); }
    function send(peerId, paths) {
        if (root.noxd && peerId && paths && paths.length > 0) {
            root.noxd.runAction({ transfer_send: { peer_id: peerId, paths: paths } });
            return true;
        }
        return false;
    }
    function accept(sessionId) { if (root.noxd) root.noxd.runAction({ transfer_accept: { session_id: sessionId } }); }
    function decline(sessionId) { if (root.noxd) root.noxd.runAction({ transfer_decline: { session_id: sessionId } }); }
    function cancel(sessionId) { if (root.noxd) root.noxd.runAction({ transfer_cancel: { session_id: sessionId } }); }
}
