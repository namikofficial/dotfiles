// Themed text input field with Material 3 styling.
// Stolen from Caelestia Shell's StyledTextField.qml.

import QtQuick
import QtQuick.Layouts
import "../theme" as Theme

FocusScope {
    id: root

    property string text: ""
    property string placeholderText: "Input"
    property string label: ""
    property string helperText: ""
    property bool readOnly: false
    property bool hasError: false
    property bool showClearButton: false
    property int maxLength: 0
    signal accepted()
    signal textChanged(string newText)

    implicitWidth: Theme.Tokens.scaled(280)
    implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightField + (label ? Theme.Tokens.spacingLg + 14 : 0))

    activeFocusOnTab: true
    Accessible.role: Accessible.EditableText
    Accessible.name: label || placeholderText

    function ensureVisible() {
        // no-op for now; scroll-into-view for list usage
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.Tokens.spacingXs

        Text {
            visible: root.label !== ""
            text: root.label
            color: root.hasError ? Theme.Tokens.stateDanger : root.activeFocus ? Theme.Tokens.tonalPrimary : Theme.Tokens.textSecondary
            font.pixelSize: Theme.Tokens.typographyLabelMedium
            font.family: Theme.Tokens.typographyFontFamily
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.Tokens.scaled(Theme.Tokens.heightField)
            radius: Theme.Tokens.radiusSm
            color: Theme.Tokens.surfaceSurfaceContainerHighest
            border.color: root.hasError ? Theme.Tokens.stateDanger : root.activeFocus ? Theme.Tokens.outlineFocus : Theme.Tokens.outlineSubtle
            border.width: root.activeFocus ? 2 : 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.Tokens.spacingMd
                anchors.rightMargin: Theme.Tokens.spacingSm
                spacing: Theme.Tokens.spacingSm

                TextInput {
                    id: input
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: root.text
                    placeholderText: root.placeholderText
                    readOnly: root.readOnly
                    clip: true
                    verticalAlignment: Text.AlignVCenter
                    color: root.readOnly ? Theme.Tokens.textDisabled : Theme.Tokens.textPrimary
                    font.pixelSize: Theme.Tokens.typographyBodyLarge
                    font.family: Theme.Tokens.typographyFontFamily
                    selectionColor: Theme.Tokens.withAlpha(Theme.Tokens.tonalPrimary, 0.3)
                    selectedTextColor: Theme.Tokens.textPrimary
                    activeFocusOnTab: false
                    selectByMouse: true
                    maximumLength: root.maxLength > 0 ? root.maxLength : 99999
                    onTextChanged: {
                        root.text = text
                        root.textChanged(text)
                    }
                    onAccepted: root.accepted()
                }

                Text {
                    visible: root.showClearButton && root.text !== ""
                    text: "✕"
                    color: Theme.Tokens.textMuted
                    font.pixelSize: Theme.Tokens.typographyBodyMedium
                    TapHandler { onTapped: { input.text = ""; input.forceActiveFocus() } }
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }

        Text {
            visible: root.helperText !== ""
            text: root.helperText
            color: root.hasError ? Theme.Tokens.stateDanger : Theme.Tokens.textMuted
            font.pixelSize: Theme.Tokens.typographyLabelSmall
            font.family: Theme.Tokens.typographyFontFamily
        }
    }

    Keys.onReturnPressed: root.accepted()
    Keys.onEscapePressed: root.focus = false
}
