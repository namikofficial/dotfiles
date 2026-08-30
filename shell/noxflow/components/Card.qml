import QtQuick
import "../theme" as Theme
import "."

Surface {
    id: root
    property alias content: contentItem.data
    tonalColor: Theme.Tokens.surfaceSurfaceContainer
    cornerRadius: Theme.Tokens.radiusLg
    elevationLevel: Theme.Tokens.elevationLow

    default property alias contentData: contentItem.data
    Item { id: contentItem; anchors.fill: parent; anchors.margins: Theme.Tokens.spacingLg }
}
