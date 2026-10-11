import QtQuick
import QtQuick.Layouts
import "../../theme" as Theme
import "." as Local

// UpdatesBody.qml — island dashboard for package updates.
//
// The dashboard is read-only: the update itself runs in a terminal, launched
// from the bar's update pill. This body exists so hovering the pill explains
// what pressing it will do.



ColumnLayout {
    id: root

    property var updates: null

    Layout.fillWidth: true
    spacing: Theme.Tokens.scaled(Theme.Tokens.spacingXs)

    Local.DashboardSection {
        Layout.fillWidth: true
        headline: !root.updates || !root.updates.checked
            ? "Checking package databases…"
            : root.updates.count > 0
                ? root.updates.count + " update" + (root.updates.count === 1 ? "" : "s") + " available"
                : "System packages are up to date"
        headlineColor: root.updates && root.updates.count > 0 ? Theme.Tokens.stateInfo : Theme.Tokens.textPrimary
        details: [{
            text: root.updates && root.updates.tooltip
                ? root.updates.tooltip
                : "Click the update capsule to open the updater; right-click to refresh.",
            wrap: true
        }]
    }
}