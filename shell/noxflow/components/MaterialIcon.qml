// Material Symbols icon component.
// Stolen from Caelestia Shell's MaterialIcon.qml.
// Supports text-based icons (including Nerd Font glyphs) with token-aware styling.

import QtQuick
import "../theme" as Theme

Text {
    id: root

    /// Icon glyph (Material Symbols ligature or Nerd Font character)
    property string icon: ""

    /// Icon size variant mapped to token sizes
    property string size: "md"   // xs, sm, md, lg, xl

    /// Semantic colour override (default: textPrimary)
    property color iconColor: Theme.Tokens.textPrimary

    /// Whether to use Nerd Font (true) vs Material Symbols font
    property bool nerdFont: true

    text: root.icon
    color: root.iconColor
    font.family: root.nerdFont ? "Symbols Nerd Font Mono" : "Material Symbols Outlined"
    font.pixelSize: {
        switch (root.size) {
            case "xs": return Theme.Tokens.iconXs
            case "sm": return Theme.Tokens.iconSm
            case "md": return Theme.Tokens.iconMd
            case "lg": return Theme.Tokens.iconLg
            case "xl": return Theme.Tokens.iconXl
            default: return Theme.Tokens.iconMd
        }
    }
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Text.NativeRendering
}
