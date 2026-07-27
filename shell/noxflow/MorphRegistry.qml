// MorphRegistry — singleton tracking chip screen-space geometry for morph animations.
// Bar chips register their position/size via `registerChip(id, rect)`.
// Panels read source geometry on open to animate from chip → panel.

import QtQml

QtObject {
    id: root

    property var chips: ({})  // { chipId: Qt.rect(x, y, w, h) }

    function registerChip(id, chipRect) {
        chips[id] = chipRect;
    }

    function unregisterChip(id) {
        delete chips[id];
    }

    function chipRect(id) {
        return chips[id] || Qt.rect(0, 0, 0, 0);
    }
}
