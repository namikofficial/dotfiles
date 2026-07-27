import QtQuick
import Quickshell
import "surfaces/control-center" as Surfaces

ShellRoot {
    NoxdClient { id: daemonClient; Component.onCompleted: start() }
    HyprlandModel { id: hyprlandModel }
    AudioModel { id: audioModel }
    BrightnessModel { id: brightnessModel }
    BatteryModel { id: batteryModel }
    PowerModel { id: powerModel }
    NetworkModel { id: networkModel }
    BluetoothModel { id: bluetoothModel }
    MediaModel { id: mediaModel }

    Connections {
        target: daemonClient
        function onSnapshotReceived(snapshots) {
            for (var provider in snapshots) {
                var snapshot = snapshots[provider];
                if (provider === "hyprland") hyprlandModel.applySnapshot(snapshot);
                else if (provider === "audio") audioModel.applySnapshot(snapshot);
                else if (provider === "brightness") brightnessModel.applySnapshot(snapshot);
                else if (provider === "power") { batteryModel.applySnapshot(snapshot); powerModel.applySnapshot(snapshot); }
                else if (provider === "network") networkModel.applySnapshot(snapshot);
                else if (provider === "bluetooth") bluetoothModel.applySnapshot(snapshot);
                else if (provider === "media") mediaModel.applySnapshot(snapshot);
            }
        }
    }

    // ── Control Centre (one per screen, tracked by controller) ──
    property var ccInstances: []
    property var ccFocusedScreen: null

    Variants {
        model: Quickshell.screens
        Surfaces.ControlCentre {
            required property var modelData
            screen: modelData
            noxd: daemonClient; audio: audioModel; brightness: brightnessModel
            network: networkModel; bluetooth: bluetoothModel; battery: batteryModel
            power: powerModel; hyprland: hyprlandModel
            Component.onCompleted: {
                shellRoot.ccInstances.push(this);
                shellRoot.ccFocusedScreen = this;
            }
            Component.onDestruction: {
                var idx = shellRoot.ccInstances.indexOf(this);
                if (idx >= 0) shellRoot.ccInstances.splice(idx, 1);
            }
        }
    }

    // ── Controller to find focused screen's CC ──
    function ccForScreen(screen) {
        for (var i = 0; i < ccInstances.length; i++) {
            if (ccInstances[i].screen === screen) return ccInstances[i];
        }
        return ccFocusedScreen || (ccInstances.length > 0 ? ccInstances[0] : null);
    }

    function toggleControlCentre() {
        var cc = ccForScreen(Quickshell.activeScreen || null);
        if (cc) cc.toggle();
    }

    // ── Global IPC handler for external keybind control ──
    IpcHandler {
        target: "noxctl"
        function toggleControl() { shellRoot.toggleControlCentre(); }
        function openControl()    { var cc = shellRoot.ccForScreen(null); if (cc) cc.open(); }
        function closeControl()   { var cc = shellRoot.ccForScreen(null); if (cc) cc.close(); }
    }

    Variants {
        model: Quickshell.screens
        NoxIsland {
            required property var modelData
            noxd: daemonClient; audio: audioModel; brightness: brightnessModel
            screen: modelData
        }
    }

    Variants {
        model: Quickshell.screens
        Bar {
            required property var modelData
            noxd: daemonClient; hyprland: hyprlandModel; audio: audioModel
            battery: batteryModel; network: networkModel; bluetooth: bluetoothModel; media: mediaModel
            screen: modelData
        }
    }
}
