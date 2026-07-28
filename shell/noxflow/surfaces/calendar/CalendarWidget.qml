// CalendarWidget — month grid + agenda panel.
// Super+Shift+C to open.

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../theme" as Theme
import "../../components" as Components

Item {
    id: root
    property var screen

    required property var noxd
    required property var calModel

    // ── Lifecycle ──
    Components.SurfaceLifecycle { id: lifecycle }
    property alias openProgress: lifecycle.openProgress
    Behavior on openProgress {
        NumberAnimation { duration: lifecycle.animDuration; easing.type: lifecycle.easingType }
    }

    property bool expanded: false
    property int hoveredDay: -1

    implicitWidth: expanded ? Theme.Tokens.scaled(520) : Theme.Tokens.scaled(320)
    anchors.fill: parent
    visible: lifecycle.active

    Connections {
        target: lifecycle
        function onOpened() {
            calModel.today();
            if (calModel && calModel.syncGCal) calModel.syncGCal();
        }
    }

    // ── Focus + Escape ──
    FocusScope {
        id: focusRoot
        focus: lifecycle.interactive
        anchors.fill: parent
        Keys.onEscapePressed: lifecycle.requestClose("escape")
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.Tokens.radiusXl
        color: Theme.Tokens.surfaceSurfaceContainerHigh
        border.color: Theme.Tokens.outlineDefault; border.width: 1
        opacity: root.openProgress
        scale: 0.85 + 0.15 * root.openProgress
        transformOrigin: Item.TopRight

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.Tokens.spacingLg
            spacing: Theme.Tokens.spacingMd

            // ── Header: month/year + nav ──
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: calModel.monthName(calModel.month) + " " + calModel.year
                    color: Theme.Tokens.textPrimary
                    font.family: Theme.Tokens.typographyFontFamily
                    font.pixelSize: Theme.Tokens.typographyTitleLarge
                    font.bold: true
                    Layout.fillWidth: true
                }
                Components.IconButton {
                    iconText: "◀"; accessibleName: "Previous month"
                    onClicked: { calModel.goPrevMonth(); root.showAgendaForSelected() }
                }
                Components.IconButton {
                    iconText: "●"; accessibleName: "Today"
                    onClicked: { calModel.today(); root.showAgendaForSelected() }
                }
                Components.IconButton {
                    iconText: "▶"; accessibleName: "Next month"
                    onClicked: { calModel.goNextMonth(); root.showAgendaForSelected() }
                }
                Components.IconButton {
                    iconText: root.expanded ? "▣" : "□"
                    accessibleName: root.expanded ? "Compact" : "Expand"
                    onClicked: root.expanded = !root.expanded
                }
                Components.IconButton {
                    iconText: "✕"; accessibleName: "Close"
                    onClicked: lifecycle.requestClose("closeButton")
                }
            }

            // ── Weekday labels ──
            RowLayout {
                Layout.fillWidth: true; spacing: 0
                Repeater {
                    model: calModel.weekdayLabels
                    delegate: Text {
                        required property string modelData
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: Theme.Tokens.textMuted
                        font.pixelSize: Theme.Tokens.typographyLabelSmall
                        font.family: Theme.Tokens.typographyFontFamily
                    }
                }
            }

            // ── Day grid ──
            GridLayout {
                Layout.fillWidth: true; columns: 7; columnSpacing: 0
                rowSpacing: Theme.Tokens.spacingXs

                Repeater {
                    model: calModel.firstDayOfMonth(calModel.year, calModel.month)
                    delegate: Item {
                        Layout.fillWidth: true; Layout.preferredHeight: Theme.Tokens.scaled(32)
                    }
                }

                Repeater {
                    model: calModel.daysInMonth(calModel.year, calModel.month)
                    delegate: Rectangle {
                        required property int index
                        readonly property int day: index + 1
                        readonly property bool isToday: {
                            var d = new Date();
                            return d.getFullYear() === calModel.year &&
                                   d.getMonth() === calModel.month &&
                                   d.getDate() === day;
                        }
                        readonly property bool isSelected: day === calModel.selectedDay
                        readonly property bool isHovered: day === root.hoveredDay

                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.Tokens.scaled(32)
                        radius: Theme.Tokens.radiusPill
                        color: isSelected ? Theme.Tokens.tonalPrimaryContainer
                             : isToday ? Theme.Tokens.tonalPrimary
                             : isHovered ? Theme.Tokens.surfaceSurfaceContainerHighest
                             : "transparent"

                        Text {
                            anchors.centerIn: parent; text: day
                            color: isSelected ? Theme.Tokens.tonalOnPrimaryContainer
                                 : isToday ? Theme.Tokens.tonalOnPrimary
                                 : Theme.Tokens.textPrimary
                            font.pixelSize: Theme.Tokens.typographyBodyMedium
                            font.bold: isToday || isSelected
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                            width: 4; height: 4; radius: 2
                            visible: calModel.hasEvents(calModel.year, calModel.month, day)
                            color: Theme.Tokens.tonalPrimary
                        }

                        TapHandler {
                            onTapped: { calModel.selectedDay = day; root.showAgendaForSelected(); }
                        }
                        HoverHandler {
                            onHoveredChanged: root.hoveredDay = hovered ? day : -1
                            cursorShape: Qt.PointingHandCursor
                        }
                    }
                }
            }

            // ── Agenda ──
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.expanded ? Theme.Tokens.scaled(200) : Theme.Tokens.scaled(100)
                radius: Theme.Tokens.radiusMd; color: Theme.Tokens.surfaceSurfaceContainer; clip: true

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: Theme.Tokens.spacingMd
                    spacing: Theme.Tokens.spacingSm

                    Text {
                        text: "Agenda — " + calModel.monthName(calModel.month) + " " + root.hoveredDay
                        color: Theme.Tokens.textSecondary
                        font.pixelSize: Theme.Tokens.typographyLabelLarge
                        font.family: Theme.Tokens.typographyFontFamily
                    }

                    Flickable {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        contentHeight: agendaItems.height + Theme.Tokens.spacingSm; clip: true

                        ColumnLayout {
                            id: agendaItems
                            anchors.left: parent.left; anchors.right: parent.right
                            spacing: Theme.Tokens.spacingXs

                            Repeater {
                                id: agendaRepeater
                                model: calModel.eventsForDay(calModel.year, calModel.month,
                                    root.hoveredDay >= 0 ? root.hoveredDay : calModel.selectedDay)

                                delegate: Rectangle {
                                    id: agendaCard
                                    required property var modelData
                                    property bool isExpanded: false

                                    Layout.fillWidth: true
                                    height: isExpanded
                                        ? Math.max(Theme.Tokens.scaled(Theme.Tokens.heightChip) + 24, Theme.Tokens.scaled(80))
                                        : Theme.Tokens.scaled(Theme.Tokens.heightChip)
                                    radius: Theme.Tokens.radiusSm
                                    color: Theme.Tokens.surfaceSurfaceContainerHigh

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: Theme.Tokens.spacingSm
                                        spacing: Theme.Tokens.spacingXs

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.Tokens.spacingSm

                                            Rectangle {
                                                width: 3
                                                height: isExpanded ? parent.height : Theme.Tokens.scaled(Theme.Tokens.heightChip - 16)
                                                radius: 2
                                                color: modelData.calendarColor || Theme.Tokens.tonalPrimary
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 0
                                                Text {
                                                    text: modelData.title || "Event"
                                                    color: Theme.Tokens.textPrimary
                                                    font.pixelSize: Theme.Tokens.typographyBodySmall
                                                    font.bold: true; elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: modelData.time ? modelData.time : "All day"
                                                    color: Theme.Tokens.textMuted
                                                    font.pixelSize: Theme.Tokens.typographyLabelSmall
                                                    visible: text !== ""
                                                }
                                            }

                                            Text {
                                                text: modelData.calendar || ""
                                                color: modelData.calendarColor || Theme.Tokens.tonalPrimary
                                                font.pixelSize: Theme.Tokens.typographyLabelSmall
                                                visible: text !== ""
                                            }

                                            Components.IconButton {
                                                iconText: isExpanded ? "▲" : "▼"
                                                accessibleName: isExpanded ? "Collapse" : "Expand"
                                                onClicked: isExpanded = !isExpanded
                                            }
                                        }

                                        Text {
                                            text: modelData.description || ""
                                            color: Theme.Tokens.textSecondary
                                            font.pixelSize: Theme.Tokens.typographyBodySmall
                                            wrapMode: Text.Wrap; Layout.fillWidth: true
                                            Layout.leftMargin: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
                                            visible: isExpanded && text !== ""
                                        }
                                        Text {
                                            text: modelData.location ? "📍 " + modelData.location : ""
                                            color: Theme.Tokens.textMuted
                                            font.pixelSize: Theme.Tokens.typographyLabelSmall
                                            Layout.leftMargin: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
                                            visible: isExpanded && text !== ""
                                        }
                                        Text {
                                            text: modelData.duration ? "⏱ " + modelData.duration : ""
                                            color: Theme.Tokens.textMuted
                                            font.pixelSize: Theme.Tokens.typographyLabelSmall
                                            Layout.leftMargin: Theme.Tokens.scaled(Theme.Tokens.spacingMd)
                                            visible: isExpanded && text !== ""
                                        }
                                    }

                                    TapHandler { onTapped: isExpanded = !isExpanded }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                }
                            }

                            Text {
                                text: "No events"; color: Theme.Tokens.textMuted
                                font.pixelSize: Theme.Tokens.typographyBodySmall
                                visible: agendaRepeater.count === 0
                            }
                        }
                    }
                }
            }
        }
    }

    function showAgendaForSelected() {}

    // ── Public API ──
    function toggle() { lifecycle.toggle(); }
    function open() { lifecycle.open(); }
    function close() { lifecycle.requestClose("close"); }
}
