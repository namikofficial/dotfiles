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
    property real elapsedSinceSnapshot: 0

    readonly property bool hasPlayer: !!(media.players && media.players.length > 0 && media.activePlayer !== "")
    readonly property bool isPlaying: String(media.playbackStatus || "").toLowerCase() === "playing"
    readonly property real durationSeconds: media.duration > 0 ? media.duration / 1000000 : 0
    readonly property real positionSeconds: media.position > 0 ? media.position / 1000000 : 0
    readonly property real livePositionSeconds: durationSeconds > 0
        ? Math.max(0, Math.min(durationSeconds, positionSeconds + (isPlaying ? elapsedSinceSnapshot : 0)))
        : positionSeconds
    readonly property real displayedPosition: seekTarget >= 0 ? seekTarget : livePositionSeconds
    readonly property real seekFraction: durationSeconds > 0
        ? Math.max(0, Math.min(1, displayedPosition / durationSeconds)) : 0
    readonly property bool canSeek: hasPlayer && durationSeconds > 0 && media.canSeek

    function formatTime(seconds) {
        var total = Math.max(0, Math.floor(Number(seconds) || 0))
        var minutes = Math.floor(total / 60)
        var remainder = total % 60
        return minutes + ":" + (remainder < 10 ? "0" : "") + remainder
    }

    function resetSeek() {
        seekTarget = -1
        seekBase = -1
        seekTimer.stop()
        optimisticSeekTimer.stop()
    }

    function seekTo(fraction) {
        if (!canSeek) return
        if (seekTarget < 0) seekBase = livePositionSeconds
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
                anchors.fill: parent
                anchors.margins: Theme.Tokens.spacingLg
                spacing: Theme.Tokens.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.Tokens.spacingXs

                    Text {
                        text: "NOW PLAYING"
                        color: Theme.Tokens.tonalSecondary
                        font.family: Theme.Tokens.typographyFontFamily
                        font.bold: true
                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                        font.letterSpacing: 1.2
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        visible: media.players && media.players.length > 1
                        spacing: Theme.Tokens.spacingXs

                        Repeater {
                            model: media.players
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool activeChip: modelData && modelData.name === media.activePlayer
                                Layout.preferredHeight: Theme.Tokens.scaled(24)
                                Layout.preferredWidth: Math.min(Theme.Tokens.scaled(110), playerChipText.implicitWidth + Theme.Tokens.scaled(14))
                                radius: Theme.Tokens.radiusPill
                                color: activeChip ? Theme.Tokens.tonalPrimaryContainer : Theme.Tokens.surfaceSurfaceContainer
                                border.color: activeChip ? Theme.Tokens.tonalPrimary : Theme.Tokens.outlineSubtle
                                border.width: 1

                                Text {
                                    id: playerChipText
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, parent.width - Theme.Tokens.scaled(10))
                                    text: (modelData && (modelData.identity || modelData.name)) || ""
                                    color: activeChip ? Theme.Tokens.tonalOnPrimaryContainer : Theme.Tokens.textSecondary
                                    font.family: Theme.Tokens.typographyFontFamily
                                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                                    font.bold: activeChip
                                    elide: Text.ElideRight
                                }

                                TapHandler {
                                    onTapped: {
                                        if (modelData && modelData.name && root.noxd) {
                                            root.noxd.runAction({ media_select_player: { player: String(modelData.name) } })
                                        }
                                    }
                                }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                        }
                    }

                    Components.IconButton {
                        iconText: "\uF00D"
                        accessibleName: "Close media"
                        onClicked: lifecycle.requestClose("closeButton")
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.Tokens.scaled(112)
                    spacing: Theme.Tokens.spacingMd

                    Item {
                        Layout.preferredWidth: Theme.Tokens.scaled(112)
                        Layout.preferredHeight: Theme.Tokens.scaled(112)
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.Tokens.radiusMd
                            color: Theme.Tokens.surfaceSurface2
                            border.color: Theme.Tokens.outlineSubtle
                            border.width: 1
                            clip: true

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
                            text: media.title || (root.hasPlayer ? "Active player" : "Nothing is playing")
                            color: Theme.Tokens.textPrimary
                            font.pixelSize: Theme.Tokens.typographyTitleLarge
                            font.family: Theme.Tokens.typographyDisplayFamily
                            font.bold: true
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                        Text {
                            text: media.artists && media.artists.length
                                ? media.artists.join(" · ")
                                : (root.hasPlayer ? "Unknown artist" : "Start playback in any app")
                            color: Theme.Tokens.textSecondary
                            font.family: Theme.Tokens.typographyFontFamily
                            font.pixelSize: Theme.Tokens.typographyBodySmall
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: media.album || (root.hasPlayer ? (media.identity || media.activePlayer) : "No active player")
                            color: Theme.Tokens.textMuted
                            font.family: Theme.Tokens.typographyFontFamily
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
                    readOnly: !root.canSeek
                    enabled: root.durationSeconds > 0
                    accessibleName: "Playback position"
                    fillColor: Theme.Tokens.tonalSecondary
                    onMoved: function(value) { root.seekTo(value) }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.durationSeconds > 0
                    Text {
                        text: root.formatTime(root.displayedPosition)
                        color: Theme.Tokens.textMuted
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.durationSeconds > 0 ? root.formatTime(root.durationSeconds) : "—:—"
                        color: Theme.Tokens.textMuted
                        font.family: Theme.Tokens.typographyFontFamily
                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                    }
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.Tokens.spacingLg

                    Components.IconButton {
                        enabled: root.hasPlayer
                        iconText: "⏮"
                        accessibleName: "Previous track"
                        onClicked: root.noxd.runAction({ media_previous: {} })
                    }
                    Components.IconButton {
                        enabled: root.hasPlayer
                        checked: root.isPlaying
                        iconText: root.isPlaying ? "⏸" : "▶"
                        accessibleName: root.isPlaying ? "Pause" : "Play"
                        onClicked: root.noxd.runAction({ media_play_pause: {} })
                    }
                    Components.IconButton {
                        enabled: root.hasPlayer
                        iconText: "⏭"
                        accessibleName: "Next track"
                        onClicked: root.noxd.runAction({ media_next: {} })
                    }
                }
            }
        }
    }

    Timer {
        id: playbackTickTimer
        interval: 1000
        repeat: true
        running: lifecycle.active && root.isPlaying && root.durationSeconds > 0
        onTriggered: {
            if (media.positionReceivedAtMs > 0) {
                root.elapsedSinceSnapshot = Math.max(0, (Date.now() - media.positionReceivedAtMs) / 1000)
            }
        }
    }

    Timer {
        id: seekTimer
        interval: 180
        repeat: false
        onTriggered: {
            if (root.seekTarget < 0 || !root.canSeek) return
            var base = root.seekBase >= 0 ? root.seekBase : root.livePositionSeconds
            var offset = Math.round((root.seekTarget - base) * 1000000)
            if (offset !== 0) {
                root.noxd.runAction({ media_seek: { offset_us: offset } })
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
            root.elapsedSinceSnapshot = 0
            if (root.seekTarget >= 0 && Math.abs(root.positionSeconds - root.seekTarget) < 1.5) {
                root.resetSeek()
            }
        }
        function onPositionReceivedAtMsChanged() {
            root.elapsedSinceSnapshot = 0
        }
        function onPlaybackStatusChanged() {
            root.elapsedSinceSnapshot = 0
        }
        function onTitleChanged() {
            root.elapsedSinceSnapshot = 0
            root.resetSeek()
        }
        function onActivePlayerChanged() {
            root.elapsedSinceSnapshot = 0
            root.resetSeek()
        }
        function onDurationChanged() {
            root.elapsedSinceSnapshot = 0
            root.resetSeek()
        }
    }

    Connections {
        target: lifecycle
        function onClosing() { root.resetSeek() }
    }

    function toggle() { lifecycle.toggle(); }
    function open() { lifecycle.open(); }
    function close() { lifecycle.requestClose("close"); }
}
