import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "theme" as Theme
import "components" as Components

PanelWindow {
    id: root

    required property var noxd
    required property var audio
    required property var brightness
    property bool active: false
    property bool rendered: false
    property bool expanded: true
    property bool reducedMotion: Theme.Tokens.reducedMotion
    property string activityKind: ""
    property string activityLabel: ""
    property string activityIcon: ""
    property real activityValue: 0
    property real activityMaximum: 100
    property real contentOpacity: 1
    property int lastOutputVolume: audio.outputVolume
    property bool lastOutputMuted: audio.outputMuted
    property bool lastInputMuted: audio.inputMuted

    screen: root.screen
    anchors.top: true
    anchors.left: true
    anchors.right: true
    exclusiveZone: 0
    aboveWindows: true
    focusable: false
    color: "transparent"
    visible: rendered
    implicitWidth: expanded ? Theme.Tokens.scaled(360) : Theme.Tokens.scaled(220)
    implicitHeight: Theme.Tokens.scaled(76)

    Behavior on implicitWidth {
        NumberAnimation { duration: Theme.Tokens.duration(250); easing.type: Easing.InOutCubic }
    }

    Connections {
        target: noxd
        function onEventReceived(event) { root.handleEvent(event) }
    }

    Timer {
        id: compactTimer
        interval: 2000
        repeat: false
        onTriggered: root.expanded = false
    }

    Timer {
        id: hideTimer
        interval: 2500
        repeat: false
        onTriggered: root.deactivate()
    }

    ParallelAnimation {
        id: exitAnimation
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: Theme.Tokens.duration(180); easing.type: Easing.InCubic }
        onFinished: root.rendered = false
    }

    SequentialAnimation {
        id: contentAnimation
        NumberAnimation { target: root; property: "contentOpacity"; to: 0; duration: Theme.Tokens.duration(80); easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "contentOpacity"; to: 1; duration: Theme.Tokens.duration(120); easing.type: Easing.OutCubic }
    }

    function deactivate() {
        active = false;
        if (reducedMotion) rendered = false;
        else exitAnimation.restart();
    }

    function show(kind, label, icon, value, maximum) {
        var changedKind = activityKind !== "" && activityKind !== kind;
        exitAnimation.stop();
        active = true;
        rendered = true;
        opacity = 1;
        expanded = true;
        activityKind = kind;
        activityLabel = label;
        activityIcon = icon;
        activityValue = Math.max(0, value);
        activityMaximum = Math.max(1, maximum);
        compactTimer.restart();
        hideTimer.restart();
        if (changedKind && !reducedMotion) contentAnimation.restart();
        else contentOpacity = 1;
    }

    function handleEvent(event) {
        if (!event || typeof event !== "object") return;
        if (event.provider === "brightness" && event.event_type === "brightness_changed") {
            var brightnessValue = Number(event.data.percentage);
            if (isFinite(brightnessValue)) show("brightness", "Brightness", "☼", brightnessValue, 100);
            return;
        }
        if (event.provider !== "audio" || event.event_type !== "state_changed") return;
        var data = event.data || {};
        var outputVolume = Number(data.output_volume);
        var outputMuted = data.output_muted === true;
        var inputMuted = data.input_muted === true;
        var maxVolume = Number(audio.maxVolume) || 100;
        if (isFinite(outputVolume) && outputVolume !== lastOutputVolume) {
            show("volume", "Output volume", "◉", outputVolume, maxVolume);
        } else if (outputMuted !== lastOutputMuted) {
            show("output-mute", outputMuted ? "Output muted" : "Output unmuted", outputMuted ? "⊘" : "◉", outputVolume, maxVolume);
        } else if (inputMuted !== lastInputMuted) {
            show("input-mute", inputMuted ? "Microphone muted" : "Microphone unmuted", inputMuted ? "⊗" : "◌", Number(data.input_volume) || 0, maxVolume);
        }
        if (isFinite(outputVolume)) lastOutputVolume = outputVolume;
        lastOutputMuted = outputMuted;
        lastInputMuted = inputMuted;
    }

    Components.PopupContainer {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.implicitWidth
        height: root.implicitHeight
        opacity: root.contentOpacity

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.Tokens.scaled(Theme.Tokens.spacingLg)
            anchors.rightMargin: Theme.Tokens.scaled(Theme.Tokens.spacingLg)
            spacing: Theme.Tokens.scaled(Theme.Tokens.spacingMd)

            Text {
                text: root.activityIcon
                color: Theme.Tokens.tonalPrimary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.iconLg
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.Tokens.scaled(Theme.Tokens.spacingXs)
                Text {
                    text: root.expanded ? root.activityLabel : root.activityLabel.replace("Output ", "")
                    color: Theme.Tokens.textPrimary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyLabelLarge
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 5
                    radius: 3
                    color: Theme.Tokens.outlineSubtle
                    Rectangle {
                        width: parent.width * Math.min(1, root.activityValue / root.activityMaximum)
                        height: parent.height
                        radius: parent.radius
                        color: Theme.Tokens.tonalPrimary
                        Behavior on width {
                            NumberAnimation { duration: Theme.Tokens.duration(120); easing.type: Easing.OutCubic }
                        }
                    }
                }
            }

            Text {
                text: Math.round(root.activityValue) + "%"
                color: Theme.Tokens.textSecondary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyLabelLarge
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
