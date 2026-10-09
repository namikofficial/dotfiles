import QtQuick
import QtQuick.Layouts
import "../theme" as Theme
import "../components" as Components
import "IslandRoutes.js" as Routes
import "." as Local
import "../surfaces/island" as IslandSurface

// IslandCard.qml — the island's visible surface.
//
// Split out of NoxIsland.qml (now island/IslandHost.qml). The host owns the
// state machine and this owns the pixels: the compact activity row, the
// dashboard chrome, and the input handlers.
//
// Every label, icon and route comes from IslandRoutes.js, so a kind that no
// producer triggers cannot appear here.



Rectangle {
    id: root

    // ── Inputs ──
    property var screen: null
    property string islandState: "idle"
    property bool expanded: false
    property bool visualExpanded: false
    property bool dashboardVisible: false
    property bool launcherVisible: false
    property bool pinned: false
    property bool reducedMotion: false

    property string activityLabel: ""
    property real activityValue: 0
    property real activityMaximum: 100
    property int displayPercent: 0

    property bool dashboardStatusVisible: false
    property string dashboardStatusText: ""
    property real dashboardStatusValue: 0
    property real dashboardStatusMaximum: 1

    property date now: new Date()
    property string activeApp: ""
    property string activeWin: ""

    property var hyprland: null
    property var systemModel: null
    property var network: null
    property var bluetooth: null
    property var audio: null
    property var battery: null
    property var notificationModel: null
    property var updates: null

    property real pillWidth: 240
    property real expandWidth: 520

    // ── Signals ──
    signal hoverEntered()
    signal hoverLeft()
    signal cardTapped()
    signal pinClicked()
    signal openClicked()
    signal closeClicked()
    // A dashboard row asked to open a specific panel.
    signal contextClicked(string panel)

    // ── Derived ──
    readonly property string label: {
        if (root.islandState === "idle")
            return Qt.formatDate(root.now, "ddd d") + " · " + Qt.formatTime(root.now, "HH:mm");
        var route = Routes.route(root.islandState);
        // A route with a label override beats the raw activity label; the
        // activity label is what a specific OSD set.
        return root.activityLabel !== "" ? root.activityLabel : route.label;
    }
    readonly property string subLabel: root.islandState === "idle" ? root.idleSubLabel() : ""
    readonly property string icon: root.iconForState(root.islandState)
    readonly property bool canOpen: !!Routes.panel(root.islandState)

    /// Whether this kind reports a measurable value (a progress bar). Kinds
    /// that do not — idle, the clock, dashboard bodies, media titles — must not
    /// draw one.
    readonly property bool showsProgress: {
        if (root.activityMaximum <= 1 || root.activityValue < 0) return false;
        return ["volume", "brightness", "output-mute", "input-mute",
                "media", "battery-warning", "timer"].indexOf(root.islandState) >= 0;
    }

    function idleSubLabel() {
        var parts = [Qt.formatDate(root.now, "ddd, d MMM")];
        if (root.activeApp !== "") {
            parts.push(root.activeApp);
            if (root.activeWin !== "" && root.activeWin !== root.activeApp) parts.push(root.activeWin);
        } else if (root.activeWin !== "") {
            parts.push(root.activeWin);
        }
        parts.push("Enter opens calendar");
        return parts.join("  ·  ");
    }

    function iconForState(state) {
        // The glyph table lives in IslandRoutes.js. It used to be duplicated
        // here as an `ICONS` map — an illegal QML property name (upper case)
        // and a second copy that could drift from the routes table.
        return Routes.icon(state) || Routes.icon("idle");
    }



    // ── Geometry ──
    anchors.centerIn: parent
    // A fixed width per state. Measuring `islandContent.implicitWidth` here was
    // circular — that row is `anchors.fill: parent` — so the card settled on
    // its minimum pill width while the row laid out at full label width and the
    // clock overflowed onto the leading icon. The label elides instead.
    width: root.launcherVisible ? Math.min(parent.width - Theme.Tokens.scaled(24), Theme.Tokens.scaled(Theme.Tokens.islandLauncherWidth))
        : root.dashboardVisible ? root.expandWidth
        : root.visualExpanded ? root.expandWidth
        : root.expanded ? Math.min(root.expandWidth, Theme.Tokens.scaled(Theme.Tokens.islandActivityMaxWidth))
        : root.islandState !== "idle"
            ? Math.min(Theme.Tokens.scaled(Theme.Tokens.islandCompactMaxWidth),
                       Math.max(Theme.Tokens.scaled(Theme.Tokens.islandCompactMinWidth), root.pillWidth))
            : root.pillWidth
    height: parent.height
    radius: root.launcherVisible || root.visualExpanded ? Theme.Tokens.radiusXl : Theme.Tokens.radiusPill
    color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, Theme.Tokens.glassPanelAlpha)
    border.color: Theme.Tokens.glass(Theme.Tokens.outlineDefault, Theme.Tokens.glassBorderAlpha)
    border.width: 1
    Accessible.role: Accessible.Button
    Accessible.name: root.label + (root.pinned ? ", pinned. Activate to unpin" : ". Activate to pin")

    Behavior on width { enabled: !root.reducedMotion; NumberAnimation { duration: Theme.Tokens.islandExpandDuration; easing.type: Easing.OutCubic } }
    Behavior on radius { enabled: !root.reducedMotion; NumberAnimation { duration: Theme.Tokens.islandExpandDuration; easing.type: Easing.OutCubic } }

    // ── Compact activity row ──
    RowLayout {
        id: islandContent
        visible: !root.launcherVisible && !root.dashboardVisible
        anchors.fill: parent
        anchors.margins: root.visualExpanded ? Theme.Tokens.spacingLg : Theme.Tokens.spacingSm
        spacing: root.visualExpanded ? Theme.Tokens.spacingMd : Theme.Tokens.spacingSm

        Text {
            text: root.icon
            color: Theme.Tokens.tonalPrimary
            font.family: Theme.Tokens.iconFont
            font.pixelSize: root.visualExpanded ? Theme.Tokens.iconLg : Theme.Tokens.iconSm
            Layout.alignment: Qt.AlignVCenter
            // A fixed slot that the layout may not shrink below. Without a
            // minimum the RowLayout compressed this item under the available
            // width and the glyph drew outside its own box, on top of the
            // label. Idle hides the icon entirely: the label is already a
            // clock, so the glyph is pure overlap risk.
            visible: root.icon !== "" && root.islandState !== "idle"
            Layout.preferredWidth: Math.max(
                implicitWidth, Theme.Tokens.scaled(root.visualExpanded ? 22 : 16))
            Layout.minimumWidth: Layout.preferredWidth
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: root.visualExpanded ? Theme.Tokens.scaled(Theme.Tokens.spacingXs) : 0

            Text {
                text: root.label
                color: Theme.Tokens.textPrimary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: root.islandState === "idle"
                    ? Theme.Tokens.typographyTitleMedium
                    : root.visualExpanded ? Theme.Tokens.typographyLabelLarge : Theme.Tokens.typographyBodySmall
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                visible: root.islandState === "idle" && root.visualExpanded
                text: root.subLabel
                color: Theme.Tokens.textSecondary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyLabelSmall
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            // Only for kinds that report a value. `activityMaximum` defaults
            // to 100, so the previous `activityMaximum > 1` guard was true
            // in idle and drew an empty full-width track under the clock.
            Components.Slider {
                Layout.fillWidth: true
                readOnly: true
                accessibleName: "Island progress"
                visible: root.showsProgress
                from: 0
                to: Math.max(1, root.activityMaximum)
                value: root.activityValue
                fillColor: root.islandState === "brightness" ? Theme.Tokens.stateWarning
                    : root.islandState === "battery-warning" ? Theme.Tokens.stateDanger
                    : Theme.Tokens.tonalPrimary
            }
        }

        Text {
            visible: !root.visualExpanded && root.islandState !== "idle" && root.activityMaximum > 1
            text: root.displayPercent + "%"
            color: Theme.Tokens.textSecondary
            font.family: Theme.Tokens.typographyFontFamily
            font.pixelSize: Theme.Tokens.typographyLabelSmall
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            visible: root.pinned
            text: ""
            color: Theme.Tokens.tonalPrimary
            font.family: Theme.Tokens.iconFont
            font.pixelSize: Theme.Tokens.iconXs
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            visible: root.visualExpanded && root.canOpen
            text: ""
            color: Theme.Tokens.textSecondary
            font.family: Theme.Tokens.iconFont
            font.pixelSize: Theme.Tokens.iconSm
            Layout.alignment: Qt.AlignVCenter
        }
    }

    // ── Dashboard ──
    ColumnLayout {
        id: dashboardContent
        visible: root.dashboardVisible && !root.launcherVisible
        anchors.fill: parent
        anchors.margins: Theme.Tokens.scaled(16)
        spacing: Theme.Tokens.scaled(8)

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: root.icon
                color: Theme.Tokens.tonalPrimary
                font.family: Theme.Tokens.iconFont
                font.pixelSize: Theme.Tokens.iconSm
            }
            Text {
                text: Routes.label(root.islandState).toUpperCase()
                color: Theme.Tokens.textPrimary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyLabelLarge
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            IslandSurface.IslandHeaderActions {
                pinned: root.pinned
                canOpen: root.canOpen
                onPinClicked: root.pinClicked()
                onOpenClicked: root.openClicked()
                onCloseClicked: root.closeClicked()
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.Tokens.outlineSubtle }

        RowLayout {
            visible: root.dashboardStatusVisible
            Layout.fillWidth: true
            spacing: Theme.Tokens.spacingSm
            Text {
                text: root.dashboardStatusText
                color: Theme.Tokens.textSecondary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyLabelSmall
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                visible: root.dashboardStatusMaximum > 1
                text: Math.round(root.dashboardStatusValue / root.dashboardStatusMaximum * 100) + "%"
                color: Theme.Tokens.tonalPrimary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyLabelSmall
            }
        }

        Local.IslandDashboardBody {
            Layout.fillWidth: true
            Layout.fillHeight: true
            kind: root.islandState
            hyprland: root.hyprland
            systemModel: root.systemModel
            network: root.network
            bluetooth: root.bluetooth
            audio: root.audio
            battery: root.battery
            notificationModel: root.notificationModel
            updates: root.updates
            activeApp: root.activeApp
            activeWin: root.activeWin
        }
    }

    // ── Input ──
    HoverHandler {
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: if (hovered) root.hoverEntered(); else root.hoverLeft()
    }

    TapHandler {
        enabled: !root.launcherVisible && !root.dashboardVisible
        onTapped: root.cardTapped()
    }
}