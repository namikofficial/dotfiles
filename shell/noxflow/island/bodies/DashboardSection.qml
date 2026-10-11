import QtQuick
import QtQuick.Layouts
import "../../theme" as Theme

// DashboardSection.qml — a labelled row inside an island dashboard body.
//
// Every dashboard body was the same ColumnLayout of Text rows with slightly
// different colours, wrapping and fonts, written out longhand each time. This
// is that one row, so a body becomes a list of values rather than a page of
// QML.



ColumnLayout {
    id: root

    spacing: Theme.Tokens.scaled(Theme.Tokens.spacingXs)

    // Headline: the answer to "what am I looking at".
    property string headline: ""
    property color headlineColor: Theme.Tokens.textPrimary
    property bool headlineBold: true

    // Detail rows, in order. Each entry: { text, color?, wrap?, dim? }.
    property var details: []

    property string footnote: ""
    property bool footnoteWrap: false

    Text {
        Layout.fillWidth: true
        text: root.headline
        visible: root.headline !== ""
        color: root.headlineColor
        font.family: Theme.Tokens.typographyFontFamily
        font.pixelSize: Theme.Tokens.typographyBodySmall
        font.bold: root.headlineBold
        elide: Text.ElideRight
    }

    Repeater {
        model: root.details || []
        delegate: Text {
            required property var modelData
            text: modelData && modelData.text !== undefined ? String(modelData.text) : ""
            visible: text !== ""
            color: modelData && modelData.color !== undefined
                ? modelData.color
                : Theme.Tokens.textSecondary
            font.family: Theme.Tokens.typographyFontFamily
            font.pixelSize: modelData && modelData.emphasis !== undefined && modelData.emphasis
                ? Theme.Tokens.typographyBodySmall
                : Theme.Tokens.typographyLabelSmall
            font.bold: !!(modelData && modelData.bold)
            elide: Text.ElideRight
            wrapMode: modelData && modelData.wrap ? Text.Wrap : Text.ElideRight
            Layout.fillWidth: true
        }
    }

    Text {
        Layout.fillWidth: true
        text: root.footnote
        visible: root.footnote !== ""
        color: Theme.Tokens.textMuted
        font.family: Theme.Tokens.typographyFontFamily
        font.pixelSize: Theme.Tokens.typographyLabelSmall
        wrapMode: root.footnoteWrap ? Text.Wrap : Text.ElideRight
    }
}