import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme" as Theme
import "../../components" as Components

Item {
    id: root
    property var screen
    required property var noxd
    required property var media
    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    Behavior on openProgress { NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType } }

    implicitWidth: Theme.Tokens.scaled(452)
    implicitHeight: Theme.Tokens.scaled(324)
    anchors.fill: parent
    visible: lifecycle.active
    property real seekTarget: -1
    property real seekBase: -1
    readonly property real durationSeconds: media.duration > 0 ? media.duration / 1000000 : 0
    readonly property real positionSeconds: media.position > 0 ? media.position / 1000000 : 0
    readonly property real displayedPosition: seekTarget >= 0 ? seekTarget : positionSeconds
    readonly property real seekFraction: durationSeconds > 0
        ? Math.max(0, Math.min(1, displayedPosition / durationSeconds)) : 0

    function formatTime(seconds) {
        var total = Math.max(0, Math.floor(Number(seconds) || 0))
        var minutes = Math.floor(total / 60)
        var remainder = total % 60
        return minutes + ":" + (remainder < 10 ? "0" : "") + remainder
    }
    function seekTo(fraction) {
        if (durationSeconds <= 0) return
        if (seekTarget < 0) seekBase = positionSeconds
        seekTarget = Math.max(0, Math.min(durationSeconds, fraction * durationSeconds))
        seekTimer.restart()
        optimisticSeekTimer.restart()
    }

    FocusScope {
        id: focusRoot; anchors.fill: parent; focus: lifecycle.interactive
        Keys.onEscapePressed: lifecycle.requestClose("escape")
        Rectangle {
            anchors.fill: parent; radius: Theme.Tokens.radiusXl
            color: Theme.Tokens.surfaceSurfaceContainerHigh
            border.color: Theme.Tokens.outlineSubtle; border.width: 1
            opacity: root.openProgress; scale: 0.92 + 0.08 * root.openProgress
            transformOrigin: Item.TopRight
            ColumnLayout {
                anchors.fill: parent; anchors.margins: Theme.Tokens.spacingLg; spacing: Theme.Tokens.spacingSm
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "NOW PLAYING"; color: Theme.Tokens.tonalSecondary; font.bold: true; font.pixelSize: Theme.Tokens.typographyLabelSmall; font.letterSpacing: 1.2; Layout.fillWidth: true }
                    Components.IconButton { iconText: "✕"; accessibleName: "Close media"; onClicked: lifecycle.requestClose("closeButton") }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.Tokens.scaled(112)
                    spacing: Theme.Tokens.spacingMd
                    Item {
                        Layout.preferredWidth: Theme.Tokens.scaled(112)
                        Layout.preferredHeight: Theme.Tokens.scaled(112)
                        Rectangle { anchors.fill: parent; radius: Theme.Tokens.radiusMd; color: Theme.Tokens.surfaceSurface2; clip: true
                            Image {
                                id: artworkImage
                                anchors.fill: parent
                                source: media.artwork || ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize: Qt.size(Theme.Tokens.scaled(224), Theme.Tokens.scaled(224))
                                visible: status === Image.Ready
                            }
                            Text {
                                anchors.centerIn: parent
                                text: "♫"
                                color: Theme.Tokens.tonalPrimary
                                font.pixelSize: Theme.Tokens.scaled(42)
                                visible: artworkImage.status !== Image.Ready
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.Tokens.spacingXs
                        Text {
                            text: media.title || "Nothing is playing"
                            color: Theme.Tokens.textPrimary
                            font.pixelSize: Theme.Tokens.typographyTitleLarge
                            font.family: Theme.Tokens.typographyDisplayFamily
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                        Text {
                            text: media.artists && media.artists.length ? media.artists.join(" · ") : "Start playback in any app"
                            color: Theme.Tokens.textSecondary
                            font.pixelSize: Theme.Tokens.typographyBodySmall
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: media.album || (media.players && media.players.length ? media.activePlayer : "No active player")
                            color: Theme.Tokens.textMuted
                            font.pixelSize: Theme.Tokens.typographyLabelSmall
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
                Components.Slider {
                    Layout.fillWidth: true
                    visible: root.durationSeconds > 0
                    value: root.seekFraction
                    from: 0
                    to: 1
                    enabled: root.durationSeconds > 0
                    accessibleName: "Playback position"
                    fillColor: Theme.Tokens.tonalSecondary
                    onMoved: function(value) { root.seekTo(value) }
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.durationSeconds > 0
                    Text { text: root.formatTime(root.displayedPosition); color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                    Item { Layout.fillWidth: true }
                    Text { text: root.durationSeconds > 0 ? root.formatTime(root.durationSeconds) : "—:—"; color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.Tokens.spacingLg
                    Components.IconButton { enabled: media.players && media.players.length > 0; iconText: "⏮"; accessibleName: "Previous track"; onClicked: root.noxd.runAction({media_previous:{}}) }
                    Components.IconButton {
                        enabled: media.players && media.players.length > 0
                        iconText: media.playbackStatus === "playing" ? "⏸" : "▶"
                        accessibleName: media.playbackStatus === "playing" ? "Pause" : "Play"
                        onClicked: root.noxd.runAction({media_play_pause:{}})
                    }
                    Components.IconButton { enabled: media.players && media.players.length > 0; iconText: "⏭"; accessibleName: "Next track"; onClicked: root.noxd.runAction({media_next:{}}) }
                }
            }
        }
    }
    Timer {
        id: seekTimer
        interval: 180
        repeat: false
        onTriggered: {
            if (root.seekTarget < 0 || root.durationSeconds <= 0) return
            var base = root.seekBase >= 0 ? root.seekBase : root.positionSeconds
            var offset = Math.round((root.seekTarget - base) * 1000000)
            if (offset !== 0) {
                root.noxd.runAction({media_seek:{offset_us: offset}})
                root.seekBase = root.seekTarget
            }
        }
    }
    Timer {
        id: optimisticSeekTimer
        interval: 1500
        repeat: false
        onTriggered: { root.seekTarget = -1; root.seekBase = -1 }
    }
    Connections {
        target: media
        function onPositionChanged() {
            if (root.seekTarget >= 0 && Math.abs(root.positionSeconds - root.seekTarget) < 1.5) {
                root.seekTarget = -1
                root.seekBase = -1
                seekTimer.stop()
                optimisticSeekTimer.stop()
            }
        }
    }
    function toggle() { lifecycle.toggle(); }
    function open() { lifecycle.open(); }
    function close() { lifecycle.requestClose("close"); }
}
