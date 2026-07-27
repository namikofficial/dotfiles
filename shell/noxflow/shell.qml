import QtQuick
import Quickshell

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
