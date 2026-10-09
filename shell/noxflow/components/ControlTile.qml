// Tiled quick-control button for Control Centre.
import QtQuick
import QtQuick.Layouts
import "../theme" as Theme

Rectangle {
    id: root
    property string icon: "•"
    property string label: ""
    property string subtitle: ""
    property bool active: true
    property color statusColor: Theme.Tokens.textSecondary
    property bool showToggle: false
    property bool toggleChecked: false
    property bool hovered: false
    property bool pressed: false
    signal clicked()
    signal toggleChanged(bool value)

    activeFocusOnTab: root.active
    Accessible.role: root.showToggle ? Accessible.CheckBox : Accessible.Button
    Accessible.name: root.label + (root.subtitle !== "" ? ", " + root.subtitle : "")
    Accessible.checked: root.showToggle && root.toggleChecked

    // Two lines of copy plus vertical padding need more than the old 52px
    // tile; the previous height made subtitles collide with the next row.
    //
    // implicitHeight, not height: every tile sits directly in a ColumnLayout,
    // and a layout assigns `height` to its children — overwriting a manually
    // set height with the item's implicitHeight, which for a bare Rectangle is
    // 0. The tile collapsed, the RowLayout had no room, and the label and icon
    // were painted on top of each other with the card background nowhere to be
    // seen.
    implicitHeight: Theme.Tokens.scaled(68)
    // The layout also owns width, so fill it rather than defaulting to 0.
    Layout.fillWidth: true
    radius: Theme.Tokens.radiusMd
    color: root.pressed ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHighest, 0.86) : root.hovered ? Theme.Tokens.glass(Theme.Tokens.surfaceSurfaceContainerHigh, 0.76) : Theme.Tokens.glass(Theme.Tokens.surfaceSurface, Theme.Tokens.glassCardAlpha)
    border.color: Theme.Tokens.glass(Theme.Tokens.outlineSubtle, Theme.Tokens.glassBorderAlpha)
    border.width: 1
    scale: root.pressed ? 0.985 : root.hovered ? 1.01 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.Tokens.durationShort; easing.type: Easing.OutCubic } }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.Tokens.spacingMd
        spacing: Theme.Tokens.spacingMd
        Text {
            text: root.icon
            color: root.statusColor
            // The icon font is not optional here. Without it the Text renders in
            // the app's monospace face, which has none of the Nerd Font private
            // use codepoints every icon in this shell is written in — the glyph
            // simply came out blank, with no error and no tofu box.
            font.family: Theme.Tokens.iconFont
            font.pixelSize: Theme.Tokens.iconMd
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.Tokens.scaled(3)
            Text {
                text: root.label
                color: Theme.Tokens.textPrimary
                font.pixelSize: Theme.Tokens.typographyBodyMedium
                font.family: Theme.Tokens.typographyFontFamily
                elide: Text.ElideRight
            }
            Text {
                visible: root.subtitle !== ""
                text: root.subtitle
                color: Theme.Tokens.textMuted
                font.pixelSize: Theme.Tokens.typographyLabelSmall
                elide: Text.ElideRight
            }
        }
        Toggle {
            id: controlToggle
            visible: root.showToggle
            checked: root.toggleChecked
            accessibleName: root.label
            onToggled: function(value) { root.toggleChanged(value) }
        }
    }
    TapHandler {
        onPressedChanged: root.pressed = pressed
        onTapped: { if (root.active && !root.showToggle) root.clicked() }
    }
    HoverHandler { cursorShape: Qt.PointingHandCursor; onHoveredChanged: root.hovered = hovered }
    Keys.onSpacePressed: root.activate()
    Keys.onReturnPressed: root.activate()

    function activate() {
        if (!root.active) return;
        root.forceActiveFocus();
        if (root.showToggle) root.toggleChanged(!root.toggleChecked);
        else root.clicked();
    }
}
