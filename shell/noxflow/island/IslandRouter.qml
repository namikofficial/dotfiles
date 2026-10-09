import QtQml
import "IslandRoutes.js" as Routes

// IslandRouter.qml — routes an island kind to its panel, and opens it.
//
// All routing knowledge lives in IslandRoutes.js. This component is the only
// thing that touches shellRoot.coordinator on the island's behalf, so there
// is one place to look when "clicking the island opened the wrong panel".



QtObject {
    id: root

    // The island's current kind. Set by the host.
    property string kind: "idle"
    // Geometry the panel should morph out of.
    property var geometry: null
    property string monitorName: ""

    // Called instead of opening a panel, for kinds whose action is external
    // (the update terminal).
    property var externalAction: null

    readonly property bool isUpdate: Routes.isUpdateSentinel(Routes.panel(root.kind))
    readonly property bool hasPanel: !!Routes.panel(root.kind)


    function open() {
        if (root.isUpdate) {
            if (root.externalAction) root.externalAction();
            return;
        }
        var panel = Routes.panel(root.kind);
        if (!panel) return;
        shellRoot.coordinator.toggle(panel, root.monitorName, root.geometry, Routes.section(root.kind));
    }
}