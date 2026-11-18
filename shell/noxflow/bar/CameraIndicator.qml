import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../theme" as Theme
import "." as Local
import "../components" as Components

// Show camera use only while a camera source is actively streaming.
Local.BarStatusPill {
    id: root

    visible: root.cameraInUse
    occupied: true
    railItem: true
    minimumWidth: Theme.Tokens.scaled(40)
    horizontalPadding: Theme.Tokens.scaled(10)
    tooltipText: "Camera in use"

    property bool cameraInUse: false
    readonly property int pollIntervalMs: 4000

    function poll() {
        if (probe.running) return;
        probe.runShell(
            "pw-dump 2>/dev/null | jq -r "
            + "'.[] | select(.type == \"PipeWire:Interface:Node\") "
            + "| select(.info.state == \"running\") "
            + "| .info.props as $p "
            + "| select($p[\"media.class\"] == \"Video/Source\" "
            + "and $p[\"media.role\"] == \"Camera\") | \"in-use\"' "
            + "| head -n 1");
    }

    Component.onCompleted: Qt.callLater(root.poll)

    property Components.Command probe: Components.Command {
        label: "Camera activity probe"
        onExited: function (code) {
            root.cameraInUse = code === 0 && root.probe.output.trim() === "in-use";
            pollTimer.restart();
        }
    }

    Timer {
        id: pollTimer
        interval: root.pollIntervalMs
        repeat: true
        running: true
        onTriggered: root.poll()
    }

    Text {
        text: "\uF03D"
        color: Theme.Tokens.stateDanger
        font.family: Theme.Tokens.iconFont
        font.pixelSize: Theme.Tokens.iconSm
    }
}
