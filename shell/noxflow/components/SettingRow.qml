import QtQuick
import QtQuick.Layouts
import "../theme" as Theme

// One settings row: a label on the left, the current value next to it, and a
// trailing control supplied by the caller.
//
// This exists because the same three-part row was hand-written dozens of times
// (label Text with Layout.fillWidth, a dimmed current-value Text with a fixed
// preferred width, then the control), and every copy drifted: some had no
// description slot, some forgot the value column, some let the label be
// squeezed to zero by a wide control.
//
// Usage — the control is the default property, so it just goes in the body:
//
//   SettingRow {
//       label: "Reduced motion"
//       valueText: Theme.Tokens.reducedMotion ? "On" : "Off"
//       Toggle { checked: Theme.Tokens.reducedMotion; onToggled: … }
//   }
Item {
    id: root
    property string label: ""
    // Optional second line under the label. Hidden when empty.
    property string description: ""
    // Optional dimmed current-value column, right-aligned before the control.
    property string valueText: ""
    property int valueWidth: Theme.Tokens.scaled(96)

    implicitHeight: layout.implicitHeight
    // The caller's control lands here, after the value column.
    default property alias control: controlSlot.data

    RowLayout {
        id: layout
        anchors.fill: parent
        spacing: Theme.Tokens.spacingMd

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                text: root.label
                color: Theme.Tokens.textPrimary
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyBodyMedium
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Text {
                text: root.description
                visible: root.description !== ""
                color: Theme.Tokens.textMuted
                font.family: Theme.Tokens.typographyFontFamily
                font.pixelSize: Theme.Tokens.typographyLabelSmall
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }

        Text {
            text: root.valueText
            visible: root.valueText !== ""
            color: Theme.Tokens.textSecondary
            font.family: Theme.Tokens.typographyFontFamily
            font.pixelSize: Theme.Tokens.typographyBodySmall
            Layout.preferredWidth: root.valueWidth
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }

        RowLayout {
            id: controlSlot
            spacing: Theme.Tokens.spacingXs
        }
    }
}