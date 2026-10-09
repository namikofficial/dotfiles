import QtQuick
import QtQuick.Layouts
import "../../theme" as Theme
import "." as Local

// ProviderHealthBody.qml — island dashboard shown when a provider is degraded.
//
// Deliberately does not guess at a cause. It says which condition is true and
// points at the control panel, rather than inventing a status the daemon never
// reported.



ColumnLayout {
    id: root

    Layout.fillWidth: true
    spacing: Theme.Tokens.scaled(Theme.Tokens.spacingXs)

    Local.DashboardSection {
        Layout.fillWidth: true
        headline: "One or more desktop data providers are degraded"
        headlineColor: Theme.Tokens.stateWarning
        details: [{
            text: "Open System controls for the current source status. Unavailable values stay marked rather than being guessed.",
            wrap: true
        }]
    }
}