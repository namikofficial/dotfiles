import QtQml
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property bool apiReachable: false
    property bool serviceActive: false
    property string myId: ""
    property string myName: ""
    property int uptime: 0
    property var folders: []
    property var devices: []
    property var recentEvents: []
    property string lastError: ""
    property bool refreshing: false
    readonly property bool syncing: folders.some(function(f) { return f.state === "syncing" || f.state === "scanning"; })
    readonly property bool hasErrors: folders.some(function(f) { return f.state === "error"; }) || lastError !== ""
    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/syncthing-rest.sh"

    property string buffer: ""
    property Process request: Process {
        running: false
        stdout: SplitParser { splitMarker: "\n"; onRead: function(data) { root.buffer += String(data || ""); } }
        onExited: function(code) {
            root.apiReachable = code === 0;
            root.lastError = code === 0 ? "" : "Syncthing is unavailable";
            if (code === 0 && root.buffer.trim() !== "") {
                try { root.applySnapshot(JSON.parse(root.buffer)); } catch (e) { root.lastError = "Invalid Syncthing response"; }
            }
            root.buffer = "";
            root.refreshing = false;
        }
    }
    property Process serviceProbe: Process {
        running: false
        stdout: SplitParser { splitMarker: "\n"; onRead: function(data) { root.serviceActive = String(data).trim() === "active"; } }
    }
    property Process openUi: Process { running: false; command: ["sh", "-c", Quickshell.env("HOME") + "/.config/hypr/scripts/syncthing-control.sh open-ui"] }
    property Timer pollTimer: Timer {
        interval: 5000; repeat: true; running: root.refreshing
        onTriggered: root.refresh()
    }

    function applySnapshot(value) {
        apiReachable = value.apiReachable === true;
        myId = String(value.myId || ""); myName = String(value.myName || "");
        uptime = Number(value.uptime || 0);
        folders = Array.isArray(value.folders) ? value.folders : [];
        devices = Array.isArray(value.devices) ? value.devices : [];
        recentEvents = Array.isArray(value.events) ? value.events.slice(-12).reverse() : [];
    }
    function refresh() {
        if (request.running) return;
        serviceProbe.command = ["systemctl", "--user", "is-active", "syncthing.service"];
        serviceProbe.running = true;
        buffer = ""; request.command = [script, "snapshot"]; request.running = true;
    }
    function start() { refresh(); }
    function setRefreshing(value) { refreshing = value; if (value) refresh(); }
    function run(action, id) { request.command = id ? [script, action, id] : [script, action]; request.running = true; Qt.callLater(refresh); }
    function pauseFolder(id) { run("pause", id); }
    function resumeFolder(id) { run("resume", id); }
    function rescanFolder(id) { run("rescan", id); }
    function toggleService() { run("toggle"); }
    function restartService() { run("restart"); }
    function openUI() { openUi.running = true; }
}
