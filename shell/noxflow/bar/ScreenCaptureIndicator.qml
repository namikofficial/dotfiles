import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../theme" as Theme
import "." as Local
import "../components" as Components

// Detect an active screen capture stream created through the PipeWire portal.
Local.BarStatusPill {
    id: root

    visible: root.captureActive
    occupied: true
    railItem: true
    minimumWidth: Theme.Tokens.scaled(40)
    horizontalPadding: Theme.Tokens.scaled(10)
    tooltipText: "Screen capture or sharing is active"

    property bool captureActive: false
    readonly property int pollIntervalMs: 3000

    function poll() {
        if (probe.running) return;
        probe.runShell(
            "pw-dump 2>/dev/null | jq -r "
            + "'any(.[]; .type == \"PipeWire:Interface:Node\" "
            + "and .info.state == \"running\" "
            + "and .info.props[\"media.class\"] == \"Video/Source\" "
            + "and ((.info.props[\"media.role\"] // \"\") == \"Screen\" "
            + "or (.info.props[\"node.name\"] // \"\" | startswith(\"xdg-desktop-portal\")) "
            + "or (.info.props[\"media.name\"] // \"\" | startswith(\"xdpw-stream-\"))))'");
    }

    Component.onCompleted: Qt.callLater(root.poll)

    property Components.Command probe: Components.Command {
        label: "Screen capture activity probe"
        onExited: function (code) {
            root.captureActive = code === 0 && root.probe.output.trim() === "true";
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
        text: "\uF108"
        color: Theme.Tokens.stateDanger
        font.family: Theme.Tokens.iconFont
        font.pixelSize: Theme.Tokens.iconSm
    }
}
