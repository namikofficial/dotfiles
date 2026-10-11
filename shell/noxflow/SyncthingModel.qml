import QtQml
import QtQuick
import Quickshell
import Quickshell.Io
import "ModelUtils.js" as Utils
import "components" as Components

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

    property Components.Command request: Components.Command {
        label: "Syncthing snapshot"
        onExited: function(code) {
            root.apiReachable = code === 0;
            root.lastError = code === 0 ? "" : root.request.failureText();
            if (code === 0 && root.request.output.trim() !== "") {
                try { root.applySnapshot(JSON.parse(root.request.output)); }
                catch (e) {
                    root.lastError = "Invalid Syncthing response"
                        + (root.request.errorOutput.trim() ? ": " + root.request.errorOutput.trim() : "");
                }
            }
            root.refreshing = false;
        }
    }
    property Components.Command serviceProbe: Components.Command {
        label: "Syncthing service state"
        onExited: function() { root.serviceActive = root.serviceProbe.output.trim() === "active" }
    }
    property Components.Command openUi: Components.Command {
        label: "Open Syncthing UI"
        command: ["sh", "-c", Quickshell.env("HOME") + "/.config/hypr/scripts/syncthing-control.sh open-ui"]
    }
    property Timer pollTimer: Timer {
        interval: 5000; repeat: true; running: root.refreshing
        onTriggered: root.refresh()
    }

    function applySnapshot(value) {
        apiReachable = value.apiReachable === true;
        myId = String(value.myId || ""); myName = String(value.myName || "");
        uptime = Number(value.uptime || 0);
        folders = Utils.asArray(value.folders);
        devices = Utils.asArray(value.devices);
        recentEvents = Utils.asArray(value.events).slice(-12).reverse();
    }
    function refresh() {
        if (request.running) return;
        serviceProbe.run(["systemctl", "--user", "is-active", "syncthing.service"]);
        request.run([script, "snapshot"]);
    }
    function start() { refresh(); }
    function setRefreshing(value) { refreshing = value; if (value) refresh(); }
    function run(action, id) { request.command = id ? [script, action, id] : [script, action]; request.running = true; Qt.callLater(refresh); }
    function pauseFolder(id) { run("pause", id); }
    function resumeFolder(id) { run("resume", id); }
    function rescanFolder(id) { run("rescan", id); }
    function toggleService() { run("toggle"); }
    function restartService() { run("restart"); }
    function openUI() { openUi.run(["sh", "-c", Quickshell.env("HOME") + "/.config/hypr/scripts/syncthing-control.sh open-ui"]); }
}
