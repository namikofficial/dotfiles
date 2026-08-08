import QtQuick
import "../theme" as Theme

Rectangle {
    id: root
    default property alias contentData: content.data
    property bool scrim: false
    property alias contentItem: content
    color: Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh)
    radius: Theme.Tokens.radiusXl
    border.color: Theme.Tokens.glass(Theme.Tokens.outlineDefault, Theme.Tokens.glassBorderAlpha)
    border.width: 1
    opacity: enabled ? 1 : Theme.Tokens.opacityDisabled
    Item { id: content; anchors.fill: parent; anchors.margins: Theme.Tokens.spacingLg }
}
