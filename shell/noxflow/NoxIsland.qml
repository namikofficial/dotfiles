// Nox Island — live activity OSD. Auto-hides after 2s.
import QtQuick; import QtQuick.Layouts; import Quickshell; import Quickshell.Wayland
import "theme" as Theme; import "components" as Components; import "surfaces/island" as Island
PanelWindow {
    id: root; required property var noxd; required property var audio; required property var brightness
    readonly property var validStates: ["idle","volume","brightness","media","mic","recording","timer","notification","output-mute","input-mute"]
    property string islandState: "idle"; property bool rendered: false; property bool expanded: true
    property bool reducedMotion: Theme.Tokens.reducedMotion
    property string activityLabel: ""; property string activityIcon: ""; property real activityValue: 0; property real activityMaximum: 100
    property var mediaTitle: ""; property var mediaArtist: ""; property var mediaArtwork: ""; property var mediaStatus: ""; property bool mediaAvailable: false
    property int timerTotalSeconds: 0; property int timerRemainingSeconds: 0; property bool timerActive: false
    property int displayPercent: Math.round(activityMaximum > 0 ? (activityValue/activityMaximum*100) : activityValue)
    property int lastOutputVolume: audio.outputVolume; property bool lastOutputMuted: audio.outputMuted; property bool lastInputMuted: audio.inputMuted
    property bool sliderDragging: false; property real sliderTarget: -1
    // Guards to debounce daemon event spam
    property real guardVolume: -1; property real guardBrightness: -1
    property int cooldownUntil: 0

    // Window: transparent, zero-size by default (set anchors+height when shown)
    screen: root.screen; visible: rendered
    // Use height 0 when hidden, full strip when shown
    width: rendered ? 1920 : 0; height: rendered ? Theme.Tokens.scaled(76) : 0

    Component.onCompleted: { rendered = false; islandState = "idle"; guardVolume = audio.outputVolume; guardBrightness = brightness.percentage; }

    implicitWidth: expanded ? Theme.Tokens.scaled(400) : Theme.Tokens.scaled(240)
    Behavior on implicitWidth { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
    Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }

    // Daemon events
    Connections { target: noxd; function onEventReceived(e) {
        if (!e || !e.provider) return;
        // Audio
        if (e.provider === "audio" && e.data) {
            var v = Number(e.data.output_volume);
            if (isFinite(v)) { lastOutputVolume = v; lastOutputMuted = e.data.output_muted === true; lastInputMuted = e.data.input_muted === true; }
            if (isFinite(v) && Math.abs(v - guardVolume) > 1) { guardVolume = v; root.show("volume","Volume","\u25C9",v,100,5,2000); }
            else if (e.data.output_muted !== lastOutputMuted) { root.show("output-mute", e.data.output_muted ? "Muted":"Unmuted", "\u25C9", v||0, 100, 4, 2000); }
            return;
        }
        // Brightness
        if (e.provider === "brightness" && e.data) {
            var b = Number(e.data.percentage);
            if (isFinite(b) && Math.abs(b - guardBrightness) > 1) { guardBrightness = b; root.show("brightness","Brightness","\u263C",b,100,5,2000); }
            return;
        }
        // Media
        if (e.provider === "media") { var md = e.data || {}; if (md.playback_status === "playing" || md.title) { mediaTitle = md.title||""; mediaArtist = md.artists ? md.artists.join(" ") : ""; mediaArtwork = md.artwork_url||md.artwork_cache||""; mediaStatus = md.playback_status||""; mediaAvailable = true; root.show("media",mediaTitle,"\u266B",50,100,6,5000); } else if (md.playback_status === "stopped" || !md.title) { mediaAvailable = false; } return; }
        // Notifications
        if (e.provider === "notifications") { var nd = e.data||{}; root.show("notification",nd.summary||nd.app_name||"Notification","\u25C8",0,1,10,5000); }
    } }

    // Model watchers (direct fallback when daemon events are slow)
    Connections { target: audio; function onOutputVolumeChanged() {
        if (!audio.available || Date.now() < root.cooldownUntil) return;
        if (Math.abs(audio.outputVolume - guardVolume) <= 1) return;
        guardVolume = audio.outputVolume; root.show("volume","Volume","\u25C9",audio.outputVolume,audio.maxVolume||100,5,2000);
    } }
    Connections { target: brightness; function onPercentageChanged() {
        if (!brightness.available || Date.now() < root.cooldownUntil) return;
        if (Math.abs(brightness.percentage - guardBrightness) <= 1) return;
        guardBrightness = brightness.percentage; root.show("brightness","Brightness","\u263C",brightness.percentage,100,5,2000);
    } }

    function show(kind,label,icon,value,maximum,priority,timeout) {
        if (Date.now() < root.cooldownUntil) return;
        root.cooldownUntil = Date.now() + 2000;  // debounce: 2s min between shows
        rendered = true; islandState = kind; expanded = true;
        activityLabel = label; activityIcon = icon; activityValue = Math.max(0,value); activityMaximum = Math.max(1,maximum);
        hideTimer.restart();
    }
    function deactivate() { rendered = false; guardVolume = audio.outputVolume; guardBrightness = brightness.percentage; }

    // Hide timer
    property Timer hideTimer: Timer { interval: 2000; repeat: false; onTriggered: root.deactivate() }

    // Slider commit
    Timer { id: sliderCommitTimer; interval: 80; repeat: false; onTriggered: {
        if (root.sliderTarget < 0) return; var c = Math.max(0,Math.min(1,root.sliderTarget));
        if (islandState==="volume"&&root.noxd&&root.noxd.connected) root.noxd.runAction({ audio_set_volume: { target:"output", volume:Math.round(c*100) } });
        else if (islandState==="brightness"&&root.noxd&&root.noxd.connected) root.noxd.runAction({ brightness_set: { percentage:Math.round(c*root.activityMaximum) } });
    } }
    function commitSlider(v) { root.sliderTarget = v; sliderCommitTimer.restart(); }

    // UI
    Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusXl; color: Theme.Tokens.surfaceSurfaceContainerHigh; border.color: Theme.Tokens.outlineDefault; border.width: 1
        Item { anchors.fill: parent; anchors.margins: Theme.Tokens.spacingLg; clip: true
            RowLayout { anchors.fill: parent; spacing: Theme.Tokens.spacingMd
                Text { text: root.activityIcon; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconLg; Layout.alignment: Qt.AlignVCenter }
                ColumnLayout { Layout.fillWidth: true; spacing: Theme.Tokens.scaled(Theme.Tokens.spacingXs)
                    Text { text: root.activityLabel; color: Theme.Tokens.textPrimary; font.pixelSize: Theme.Tokens.typographyLabelLarge; elide: Text.ElideRight; Layout.fillWidth: true }
                    Rectangle { Layout.fillWidth: true; height: 5; radius: 3; color: Theme.Tokens.outlineSubtle; visible: root.activityMaximum > 1 && root.activityValue >= 0
                        Rectangle { width: parent.width*Math.min(1,root.activityValue/root.activityMaximum); height: parent.height; radius: parent.radius;
                            color: islandState==="volume"||islandState==="output-mute" ? Theme.Tokens.tonalPrimary : Theme.Tokens.tonalPrimary;
                            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } } } } }
                Text { text: root.displayPercent+"%"; color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyLabelLarge; Layout.alignment: Qt.AlignVCenter }
            }
        }
    }
    function formatTime(s) { var m = Math.floor(s/60); var r = s%60; return m+":"+(r<10?"0":"")+r; }
    function startTimer(s) { if (s <= 0) return; timerTotalSeconds = s; timerRemainingSeconds = s; timerActive = true; show("timer","Timer "+formatTime(s),"\u23F1",1,1,7,120000); }
    function showRecording() { show("recording","Recording","\u23FA",0,1,9,30000); }
    function stopRecording() { if (islandState === "recording") deactivate(); }
    function showNotification(s,b) { show("notification",s||"Notification","\u25C8",0,1,10,5000); }
}
