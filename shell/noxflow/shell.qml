import QtQuick
import Quickshell

ShellRoot {
    NoxdClient { id: noxd; Component.onCompleted: start() }
    HyprlandModel { id: hyprland }
    AudioModel { id: audio }
    BrightnessModel { id: brightness }
    BatteryModel { id: battery }
    PowerModel { id: power }
    NetworkModel { id: network }
    BluetoothModel { id: bluetooth }
    MediaModel { id: media }

    Connections {
        target: noxd
        function onSnapshotReceived(snapshots) {
            for (var provider in snapshots) {
                var snapshot = snapshots[provider];
                if (provider === "hyprland") hyprland.applySnapshot(snapshot);
                else if (provider === "audio") audio.applySnapshot(snapshot);
                else if (provider === "brightness") brightness.applySnapshot(snapshot);
                else if (provider === "power") { battery.applySnapshot(snapshot); power.applySnapshot(snapshot); }
                else if (provider === "network") network.applySnapshot(snapshot);
                else if (provider === "bluetooth") bluetooth.applySnapshot(snapshot);
                else if (provider === "media") media.applySnapshot(snapshot);
            }
        }
    }

    Gallery {
        client: noxd; hyprland: hyprland; audio: audio; brightness: brightness
        battery: battery; power: power; network: network; bluetooth: bluetooth; media: media
    }
}
