// WordOverlay — per-word OCR highlight overlay.
// Shows detected words as interactive boxes. Tap to copy, hover to highlight.
// Supports multi-word selection: Ctrl+click toggles, Shift+click extends range.
// Stolen from: QuickSnip WordOverlay.qml (touch-friendly, smart toolbar, selection handles).

import QtQuick
import QtQuick.Layouts
import "../../theme" as Theme

Item {
    id: root

    // Word data: [{x, y, w, h, text, confidence, line}]
    property var words: []
    property int hoveredIndex: -1
    property int selectedIndex: -1
    property var selectedIndices: []  // multi-select
    property int anchorIndex: -1      // shift-click anchor
    property real scaleFactor: 1.0

    // Screen-space offset of the selection region
    property real regionX: 0
    property real regionY: 0

    signal wordCopied(string text)
    signal wordSelected(int index, string text)

    // Touch-friendly minimum size
    readonly property real minTouchSize: 28

    Repeater {
        model: root.words.length

        delegate: Rectangle {
            required property int index
            readonly property var word: root.words[index]
            readonly property real dispW: Math.max(word.w * root.scaleFactor, root.minTouchSize)
            readonly property real dispH: Math.max(word.h * root.scaleFactor, root.minTouchSize)
            readonly property bool isMultiSelected: root.selectedIndices.indexOf(index) >= 0

            x: word.x * root.scaleFactor + root.regionX - dispW/2 + word.w * root.scaleFactor/2
            y: word.y * root.scaleFactor + root.regionY - dispH/2 + word.h * root.scaleFactor/2
            width: dispW
            height: dispH
            radius: 4
            color: {
                if (isMultiSelected) return Theme.Tokens.withAlpha(Theme.Tokens.tonalPrimary, 0.5);
                if (root.selectedIndex === index) return Theme.Tokens.withAlpha(Theme.Tokens.tonalPrimary, 0.4);
                if (root.hoveredIndex === index) return Theme.Tokens.withAlpha(Theme.Tokens.tonalPrimary, 0.25);
                return Theme.Tokens.withAlpha(Theme.Tokens.tonalPrimary, 0.08);
            }
            border.color: isMultiSelected || root.selectedIndex === index ? Theme.Tokens.tonalPrimary : "transparent"
            border.width: isMultiSelected || root.selectedIndex === index ? 1 : 0

            Text {
                anchors.centerIn: parent
                text: word.text
                color: Theme.Tokens.tonalOnPrimaryContainer
                font.pixelSize: Math.min(Theme.Tokens.typographyBodySmall, word.h * root.scaleFactor * 0.6)
                font.family: Theme.Tokens.typographyFontFamily
                elide: Text.ElideRight
            }

            HoverHandler {
                onHoveredChanged: root.hoveredIndex = hovered ? index : -1
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                acceptedModifiers: Qt.ControlModifier
                onTapped: {
                    // Ctrl+click: toggle this word in multi-select
                    var pos = root.selectedIndices.indexOf(index);
                    if (pos >= 0) {
                        root.selectedIndices.splice(pos, 1);
                        root.selectedIndices = root.selectedIndices.slice(); // trigger binding
                    } else {
                        root.selectedIndices = root.selectedIndices.concat([index]);
                        root.anchorIndex = index;
                    }
                }
            }
            TapHandler {
                acceptedModifiers: Qt.ShiftModifier
                onTapped: {
                    // Shift+click: extend range from anchor
                    if (root.anchorIndex < 0) root.anchorIndex = index;
                    var from = Math.min(root.anchorIndex, index);
                    var to = Math.max(root.anchorIndex, index);
                    var range = [];
                    for (var i = from; i <= to; i++) range.push(i);
                    root.selectedIndices = range;
                }
            }
            TapHandler {
                // Plain click: select single word + emit
                onTapped: {
                    root.selectedIndices = [index];
                    root.anchorIndex = index;
                    root.selectedIndex = index;
                    root.wordSelected(index, word.text);
                }
            }
        }
    }

    // ── Clear selection ──
    function clearSelection() {
        selectedIndex = -1;
        selectedIndices = [];
        anchorIndex = -1;
    }

    // ── Copy selected word(s) ──
    function copySelected() {
        if (selectedIndices.length > 0) {
            var texts = [];
            for (var i = 0; i < selectedIndices.length; i++) {
                texts.push(words[selectedIndices[i]].text);
            }
            wordCopied(texts.join(" "));
        } else if (selectedIndex >= 0 && selectedIndex < words.length) {
            wordCopied(words[selectedIndex].text);
        }
    }

    // ── Get selected text ──
    function getSelectedText() {
        if (selectedIndices.length > 0) {
            var texts = [];
            for (var i = 0; i < selectedIndices.length; i++) {
                texts.push(words[selectedIndices[i]].text);
            }
            return texts.join(" ");
        } else if (selectedIndex >= 0 && selectedIndex < words.length) {
            return words[selectedIndex].text;
        }
        return "";
    }
}
