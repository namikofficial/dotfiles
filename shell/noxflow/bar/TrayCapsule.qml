import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import "../theme" as Theme
import "../components" as Components

// TrayCapsule.qml — StatusNotifier (system tray) host for the bar.
//
// The shell had no tray at all: every tray-aware application was invisible
// unless it also published something else. Quickshell provides the
// StatusNotifier watcher, so this is the whole implementation.
//
// `SystemTray` is a **singleton** in this Quickshell version (isCreatable:
// false in its qmltypes). Declaring `SystemTray { id: model }` fails at load
// with "Element is not creatable" and takes the entire shell down with it, so
// the module is referenced directly and its `items` model is read as a
// property.
//
// Items with category `SystemServices` are hidden. They are usually background
// daemons with no useful action and they crowd out the entries a person would
// want to click.

RowLayout {
    id: root

    spacing: Theme.Tokens.scaled(Theme.Tokens.spacingSm)
    Layout.alignment: Qt.AlignVCenter
    Layout.minimumWidth: 0

    readonly property var items: SystemTray.items

    readonly property var shownItems: {
        var out = [];
        var all = root.items;
        if (!all) return out;
        for (var i = 0; i < all.length; i++) {
            if (all[i].category === SystemTrayItem.Category.SystemServices) continue;
            out.push(all[i]);
        }
        return out;
    }

    Repeater {
        model: root.shownItems

        delegate: Item {
            id: trayEntry
            required property var modelData
            required property int index

            readonly property var entry: modelData

            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Math.max(Theme.Tokens.scaled(18), icon.implicitWidth)
            implicitHeight: Theme.Tokens.scaled(Theme.Tokens.heightChip)
            visible: trayEntry.entry && trayEntry.entry.icon !== ""
            // components/Tooltip.qml gates on `target.hovered`.
            readonly property bool hovered: hoverHandler.hovered

            // StatusNotifier `icon` is a themed SVG name; Image resolves it
            // through the shell's SVG image provider. (QtQuick.Controls
            // IconImage is absent from this Qt build.)
            //
            // The explicit source size is what prevents the
            // `qt.svg.draw: buffer too big` warnings at boot: without a bound,
            // an SVG loads at its intrinsic size.
            Image {
                id: icon
                anchors.fill: parent
                anchors.margins: 1
                sourceSize.width: Theme.Tokens.scaled(18)
                sourceSize.height: Theme.Tokens.scaled(18)
                source: trayEntry.entry ? trayEntry.entry.icon : ""
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                opacity: hoverHandler.hovered || tapHandler.pressed ? 1.0 : 0.75
            }

            HoverHandler {
                id: hoverHandler
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                id: tapHandler
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onTapped: function(eventPoint, button) {
                    var entry = trayEntry.entry;
                    if (!entry) return;
                    // StatusNotifier activation takes global coordinates.
                    var point = trayEntry.mapToGlobal(trayEntry.width / 2, trayEntry.height / 2);
                    if (button === Qt.RightButton) {
                        if (entry.hasMenu && entry.menu && typeof entry.menu.display === "function")
                            entry.menu.display(entry, null);
                    } else if (typeof entry.activate === "function") {
                        entry.activate(point.x, point.y);
                    }
                }
            }

            Components.Tooltip {
                target: trayEntry
                text: trayEntry.entry ? (trayEntry.entry.tooltipTitle || trayEntry.entry.title || "") : ""
            }
        }
    }
}