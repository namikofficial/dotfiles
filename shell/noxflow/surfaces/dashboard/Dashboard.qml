// Dashboard — full-screen personal command centre.
// Super+D to open. Shows: weather, agenda, system health, git status, quick actions.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../theme" as Theme
import "../../components" as Components

PanelWindow {
    id: root

    required property var noxd
    required property var hyprland
    required property var audio
    required property var battery
    required property var network
    required property var calModel
    required property var weatherModel
    required property var systemModel

    signal requestCaptureAfterClose()

    // ── Lifecycle ──
    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress

    Behavior on openProgress {
        NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType }
    }

    property string gitBranch: ""
    property string gitStatus: ""

    property Process dashProcess: Process { command: []; running: false }

    anchors.top: true; anchors.bottom: true; anchors.left: true; anchors.right: true
    exclusiveZone: 0; aboveWindows: true; focusable: true; color: "transparent"
    visible: lifecycle.active

    Connections {
        target: lifecycle
        function onOpened() {
            calModel.today();
            refreshGit();
            if (calModel.events.length === 0) calModel.syncGCal();
        }
        function onClosed() {
            if (lifecycle.closeReason === "screenshot") root.requestCaptureAfterClose();
        }
    }

    // ── Focus + Escape ──
    FocusScope {
        id: focusRoot
        anchors.fill: parent
        focus: lifecycle.interactive
        Keys.onEscapePressed: lifecycle.requestClose("escape")
    }

    // ── Scrim ──
    Rectangle {
        anchors.fill: parent
        color: Theme.Tokens.withAlpha(Theme.Tokens.tonalBackground, 0.7)
        opacity: root.openProgress
        TapHandler { onTapped: lifecycle.requestClose("clickOutside") }
    }

    // ── Dashboard panel ──
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.85, Theme.Tokens.scaled(800))
        height: Math.min(parent.height * 0.8, Theme.Tokens.scaled(560))
        radius: Theme.Tokens.radiusXl
        color: Theme.Tokens.surfaceSurfaceContainerHigh
        border.color: Theme.Tokens.outlineDefault; border.width: 1
        scale: 0.85 + 0.15 * root.openProgress
        opacity: root.openProgress

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.Tokens.spacingXl
            spacing: Theme.Tokens.spacingLg

            // ── Header row ──
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    Text {
                        text: {
                            var h = new Date().getHours()
                            if (h < 12) return "Good morning"
                            if (h < 17) return "Good afternoon"
                            return "Good evening"
                        }
                        color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.typographyDisplayMedium
                        font.family: Theme.Tokens.typographyFontFamily
                        font.bold: true
                    }
                    Text {
                        text: Qt.formatDate(new Date(), "dddd, MMMM d")
                        color: Theme.Tokens.textSecondary
                        font.pixelSize: Theme.Tokens.typographyBodyLarge
                        font.family: Theme.Tokens.typographyFontFamily
                    }
                }

                RowLayout {
                    spacing: Theme.Tokens.spacingSm
                    visible: weatherModel && weatherModel.condition !== ""
                    Text { text: weatherModel.icon; font.pixelSize: Theme.Tokens.iconXl }
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: Math.round(weatherModel.temperature) + "°C"
                            color: Theme.Tokens.textPrimary
                            font.pixelSize: Theme.Tokens.typographyTitleLarge
                            font.bold: true
                        }
                        Text {
                            text: weatherModel.condition
                            color: Theme.Tokens.textSecondary
                            font.pixelSize: Theme.Tokens.typographyLabelMedium
                        }
                    }
                }

                RowLayout {
                    spacing: Theme.Tokens.spacingSm
                    visible: weatherModel && weatherModel.forecast && weatherModel.forecast.length > 0
                    Repeater {
                        model: weatherModel.forecast.length
                        delegate: Rectangle {
                            required property int index
                            readonly property var day: weatherModel.forecast[index]
                            implicitWidth: Theme.Tokens.scaled(80)
                            height: Theme.Tokens.scaled(64)
                            radius: Theme.Tokens.radiusMd
                            color: Theme.Tokens.surfaceSurfaceContainer
                            visible: day !== undefined
                            ColumnLayout {
                                anchors.centerIn: parent; spacing: 2
                                Text {
                                    text: day.day || ""
                                    color: Theme.Tokens.textSecondary
                                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: day.icon || "☀"
                                    font.pixelSize: Theme.Tokens.iconSm
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.fillWidth: true
                                }
                                RowLayout {
                                    spacing: 4; Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignHCenter
                                    Text {
                                        text: Math.round(day.tempHigh) + "°"
                                        color: Theme.Tokens.textPrimary
                                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                                        font.bold: true
                                    }
                                    Text {
                                        text: Math.round(day.tempLow) + "°"
                                        color: Theme.Tokens.textMuted
                                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                                    }
                                }
                                Text {
                                    text: day.precip + "%"
                                    color: Theme.Tokens.stateInfo
                                    font.pixelSize: Theme.Tokens.iconXs
                                    horizontalAlignment: Text.AlignHCenter
                                    Layout.fillWidth: true
                                    visible: day.precip > 0
                                }
                            }
                        }
                    }
                }

                Components.IconButton {
                    iconText: "✕"; accessibleName: "Close dashboard"
                    onClicked: lifecycle.requestClose("closeButton")
                }
            }

            // ── Content grid ──
            RowLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: Theme.Tokens.spacingLg

                // ── Left column: Calendar + Agenda ──
                ColumnLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    spacing: Theme.Tokens.spacingMd

                    Text {
                        text: calModel.monthName(calModel.month) + " " + calModel.year
                        color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.typographyTitleMedium
                        font.bold: true
                    }

                    GridLayout {
                        Layout.fillWidth: true; columns: 7
                        columnSpacing: 0; rowSpacing: 2
                        Repeater {
                            model: calModel.weekdayLabels
                            delegate: Text {
                                required property string modelData
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData; color: Theme.Tokens.textMuted
                                font.pixelSize: Theme.Tokens.typographyLabelSmall
                            }
                        }
                        Repeater {
                            model: calModel.firstDayOfMonth(calModel.year, calModel.month)
                            delegate: Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.Tokens.scaled(24)
                            }
                        }
                        Repeater {
                            model: calModel.daysInMonth(calModel.year, calModel.month)
                            delegate: Rectangle {
                                required property int index
                                readonly property int day: index + 1
                                readonly property bool isToday: {
                                    var d = new Date()
                                    return d.getFullYear() === calModel.year &&
                                           d.getMonth() === calModel.month &&
                                           d.getDate() === day
                                }
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.Tokens.scaled(24)
                                radius: Theme.Tokens.radiusPill
                                color: isToday ? Theme.Tokens.tonalPrimary : "transparent"
                                Text {
                                    anchors.centerIn: parent; text: day
                                    color: isToday ? Theme.Tokens.tonalOnPrimary : Theme.Tokens.textPrimary
                                    font.pixelSize: Theme.Tokens.typographyBodySmall
                                    font.bold: isToday
                                }
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom; anchors.bottomMargin: 1
                                    width: 3; height: 3; radius: 2
                                    visible: calModel.hasEvents(calModel.year, calModel.month, day)
                                    color: Theme.Tokens.tonalPrimary
                                }
                            }
                        }
                    }

                    Text {
                        text: "Today"; color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.typographyTitleMedium; font.bold: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        spacing: Theme.Tokens.spacingXs; clip: true
                        Repeater {
                            model: calModel.eventsForDay(new Date().getFullYear(), new Date().getMonth(), new Date().getDate())
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                height: Theme.Tokens.scaled(32)
                                radius: Theme.Tokens.radiusSm
                                color: Theme.Tokens.surfaceSurfaceContainer
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.Tokens.spacingSm
                                    Rectangle {
                                        width: 3; height: parent.height; radius: 2
                                        color: Theme.Tokens.tonalPrimary
                                    }
                                    Text {
                                        text: modelData.title || "Event"
                                        color: Theme.Tokens.textPrimary
                                        font.pixelSize: Theme.Tokens.typographyBodySmall
                                        elide: Text.ElideRight; Layout.fillWidth: true
                                    }
                                    Text {
                                        text: modelData.time || "all day"
                                        color: Theme.Tokens.textMuted
                                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                                    }
                                }
                            }
                        }
                        Text {
                            text: "No events today"; color: Theme.Tokens.textMuted
                            font.pixelSize: Theme.Tokens.typographyBodySmall
                            visible: calModel.eventsForDay(new Date().getFullYear(), new Date().getMonth(), new Date().getDate()).length === 0
                        }
                    }
                }

                // ── Right column: System + Quick actions ──
                ColumnLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    spacing: Theme.Tokens.spacingMd

                    Text {
                        text: "System"; color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.typographyTitleMedium; font.bold: true
                    }

                    // CPU tile
                    Rectangle {
                        Layout.fillWidth: true
                        height: Theme.Tokens.scaled(64)
                        radius: Theme.Tokens.radiusMd
                        color: Theme.Tokens.surfaceSurfaceContainer
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: Theme.Tokens.spacingSm; spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "⚡"
                                    color: (systemModel && systemModel.cpuUsage > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.tonalPrimary
                                    font.pixelSize: Theme.Tokens.iconSm
                                }
                                Text {
                                    text: "CPU"; color: Theme.Tokens.textSecondary
                                    font.pixelSize: Theme.Tokens.typographyLabelSmall; Layout.fillWidth: true
                                }
                                Text {
                                    text: systemModel ? systemModel.cpuUsage + "%" : "--"
                                    color: (systemModel && systemModel.cpuUsage > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.textPrimary
                                    font.pixelSize: Theme.Tokens.typographyBodyMedium; font.bold: true
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true; height: 4; radius: 2
                                color: Theme.Tokens.outlineSubtle
                                Rectangle {
                                    width: parent.width * Math.min(1, (systemModel ? systemModel.cpuUsage : 0) / 100)
                                    height: parent.height; radius: parent.radius
                                    color: (systemModel && systemModel.cpuUsage > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.tonalPrimary
                                }
                            }
                            Text {
                                text: systemModel ? systemModel.cpuTemp + "°C" : ""
                                color: (systemModel && systemModel.cpuTemp > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.textMuted
                                font.pixelSize: Theme.Tokens.typographyLabelSmall
                            }
                        }
                    }

                    // GPU tile
                    Rectangle {
                        Layout.fillWidth: true
                        height: Theme.Tokens.scaled(64)
                        radius: Theme.Tokens.radiusMd
                        color: Theme.Tokens.surfaceSurfaceContainer
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: Theme.Tokens.spacingSm; spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "🎮"; color: Theme.Tokens.tonalSecondary
                                    font.pixelSize: Theme.Tokens.iconSm
                                }
                                Text {
                                    text: systemModel && systemModel.gpuAvailable ? systemModel.gpuName : "GPU"
                                    color: Theme.Tokens.textSecondary
                                    font.pixelSize: Theme.Tokens.typographyLabelSmall; Layout.fillWidth: true
                                }
                                Text {
                                    text: systemModel && systemModel.gpuAvailable ? systemModel.gpuUsage + "%" : "—"
                                    color: Theme.Tokens.textPrimary
                                    font.pixelSize: Theme.Tokens.typographyBodyMedium; font.bold: true
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true; height: 4; radius: 2
                                color: Theme.Tokens.outlineSubtle
                                Rectangle {
                                    width: parent.width * Math.min(1, (systemModel ? systemModel.gpuUsage : 0) / 100)
                                    height: parent.height; radius: parent.radius
                                    color: Theme.Tokens.tonalSecondary
                                }
                            }
                            Text {
                                text: systemModel && systemModel.gpuAvailable && systemModel.gpuMemTotal > 0
                                    ? Math.round(systemModel.gpuMemUsed / 1024) + "/" + Math.round(systemModel.gpuMemTotal / 1024) + " GB" : ""
                                color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall
                            }
                        }
                    }

                    // RAM tile
                    Rectangle {
                        Layout.fillWidth: true
                        height: Theme.Tokens.scaled(64)
                        radius: Theme.Tokens.radiusMd
                        color: Theme.Tokens.surfaceSurfaceContainer
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: Theme.Tokens.spacingSm; spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "💾"
                                    color: (systemModel && systemModel.memPercent > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.tonalTertiary
                                    font.pixelSize: Theme.Tokens.iconSm
                                }
                                Text {
                                    text: "RAM"; color: Theme.Tokens.textSecondary
                                    font.pixelSize: Theme.Tokens.typographyLabelSmall; Layout.fillWidth: true
                                }
                                Text {
                                    text: systemModel ? systemModel.memPercent + "%" : "--"
                                    color: (systemModel && systemModel.memPercent > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.textPrimary
                                    font.pixelSize: Theme.Tokens.typographyBodyMedium; font.bold: true
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true; height: 4; radius: 2
                                color: Theme.Tokens.outlineSubtle
                                Rectangle {
                                    width: parent.width * Math.min(1, (systemModel ? systemModel.memPercent : 0) / 100)
                                    height: parent.height; radius: parent.radius
                                    color: (systemModel && systemModel.memPercent > 80) ? Theme.Tokens.stateDanger : Theme.Tokens.tonalTertiary
                                }
                            }
                            Text {
                                text: systemModel
                                    ? Math.round(systemModel.memUsed / 1024 / 1024) + "/" + Math.round(systemModel.memTotal / 1024 / 1024) + " GB" : ""
                                color: Theme.Tokens.textMuted; font.pixelSize: Theme.Tokens.typographyLabelSmall
                            }
                        }
                    }

                    // Battery
                    Rectangle {
                        Layout.fillWidth: true
                        height: Theme.Tokens.scaled(40)
                        radius: Theme.Tokens.radiusMd
                        color: Theme.Tokens.surfaceSurfaceContainer
                        RowLayout {
                            anchors.fill: parent; anchors.margins: Theme.Tokens.spacingMd
                            Text {
                                text: "▰"
                                color: battery.present ? Theme.Tokens.stateSuccess : Theme.Tokens.textMuted
                                font.pixelSize: Theme.Tokens.iconMd
                            }
                            Text {
                                text: "Battery"; color: Theme.Tokens.textPrimary
                                font.pixelSize: Theme.Tokens.typographyBodyMedium; Layout.fillWidth: true
                            }
                            Text {
                                text: battery.present && battery.percentage !== null ? Math.round(battery.percentage) + "%" : "—"
                                color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall
                            }
                        }
                    }

                    // Network
                    Rectangle {
                        Layout.fillWidth: true
                        height: Theme.Tokens.scaled(40)
                        radius: Theme.Tokens.radiusMd
                        color: Theme.Tokens.surfaceSurfaceContainer
                        RowLayout {
                            anchors.fill: parent; anchors.margins: Theme.Tokens.spacingMd
                            Text {
                                text: "⌁"
                                color: network.connectivity === "full" ? Theme.Tokens.stateSuccess : Theme.Tokens.textMuted
                                font.pixelSize: Theme.Tokens.iconMd
                            }
                            Text {
                                text: "Network"; color: Theme.Tokens.textPrimary
                                font.pixelSize: Theme.Tokens.typographyBodyMedium; Layout.fillWidth: true
                            }
                            Text {
                                text: network.connectedSsid || network.connectivity || "—"
                                color: Theme.Tokens.textSecondary
                                font.pixelSize: Theme.Tokens.typographyBodySmall
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Audio
                    Rectangle {
                        Layout.fillWidth: true
                        height: Theme.Tokens.scaled(40)
                        radius: Theme.Tokens.radiusMd
                        color: Theme.Tokens.surfaceSurfaceContainer
                        RowLayout {
                            anchors.fill: parent; anchors.margins: Theme.Tokens.spacingMd
                            Text {
                                text: audio.outputMuted ? "⊘" : "◉"
                                color: audio.outputMuted ? Theme.Tokens.stateWarning : Theme.Tokens.stateSuccess
                                font.pixelSize: Theme.Tokens.iconMd
                            }
                            Text {
                                text: "Volume"; color: Theme.Tokens.textPrimary
                                font.pixelSize: Theme.Tokens.typographyBodyMedium; Layout.fillWidth: true
                            }
                            Text {
                                text: audio.outputMuted ? "Muted" : audio.outputVolumePercent + "%"
                                color: Theme.Tokens.textSecondary; font.pixelSize: Theme.Tokens.typographyBodySmall
                            }
                        }
                    }

                    // Git (stub)
                    Rectangle {
                        Layout.fillWidth: true
                        height: Theme.Tokens.scaled(40)
                        radius: Theme.Tokens.radiusMd
                        color: Theme.Tokens.surfaceSurfaceContainer
                        visible: root.gitBranch !== ""
                        RowLayout {
                            anchors.fill: parent; anchors.margins: Theme.Tokens.spacingMd
                            Text { text: "⑂"; color: Theme.Tokens.tonalPrimary; font.pixelSize: Theme.Tokens.iconMd }
                            Text {
                                text: root.gitBranch; color: Theme.Tokens.textPrimary
                                font.pixelSize: Theme.Tokens.typographyBodyMedium
                                Layout.fillWidth: true; elide: Text.ElideRight
                            }
                            Text {
                                text: root.gitStatus; color: Theme.Tokens.textSecondary
                                font.pixelSize: Theme.Tokens.typographyLabelSmall
                            }
                        }
                    }

                    Components.Divider { Layout.fillWidth: true; Layout.topMargin: Theme.Tokens.spacingSm }

                    Text {
                        text: "Quick Actions"; color: Theme.Tokens.textPrimary
                        font.pixelSize: Theme.Tokens.typographyTitleMedium; font.bold: true
                    }

                    Flow {
                        Layout.fillWidth: true; spacing: Theme.Tokens.spacingSm

                        Components.TextButton {
                            text: "Lock"
                            onClicked: {
                                if (root.noxd && root.noxd.connected) root.noxd.runAction({ lock: {} })
                                lifecycle.requestClose("lock")
                            }
                        }
                        Components.TextButton {
                            text: "Suspend"
                            onClicked: {
                                if (root.noxd && root.noxd.connected) root.noxd.runAction({ suspend: {} })
                                lifecycle.requestClose("suspend")
                            }
                        }
                        Components.TextButton {
                            text: "Screenshot"
                            onClicked: lifecycle.requestClose("screenshot")
                        }
                        Components.TextButton {
                            text: "Reload shell"
                            onClicked: {
                                root.dashProcess.command = ["systemctl", "--user", "reload", "noxflow-shell"]
                                root.dashProcess.running = true
                                lifecycle.requestClose("reloadShell")
                            }
                        }
                        Components.TextButton {
                            text: "Refresh"
                            onClicked: {
                                if (root.noxd && root.noxd.connected) root.noxd.runAction({ refresh_providers: {} })
                            }
                        }
                        Components.TextButton {
                            text: "Settings"
                            onClicked: {
                                root.dashProcess.command = ["gnome-control-center"]
                                root.dashProcess.running = true
                                lifecycle.requestClose("systemSettings")
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Public API ──
    function toggle() { lifecycle.toggle() }
    function open() { lifecycle.open() }
    function close() { lifecycle.requestClose("close") }

    function refreshGit() {
        gitBranch = "main"
        gitStatus = "clean"
    }
}
