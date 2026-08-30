// SurfaceCoordinator — modal stacking and Escape routing for all NoxFlow surfaces.
//
// Types:
//   Modal — exclusive full-screen overlays (Dashboard, Overview, Launcher,
//           Capture, Settings). Opening one closes the current modal.
//   Panel — per-screen side panels (ControlCentre, NotificationCentre,
//           Calendar). May coexist with each other and with modals.
//
// Escape always targets the topmost Modal first. If no Modal is open,
// it targets the last-opened Panel.

import QtQml

QtObject {
    id: root

    enum Type { Modal, Panel }

    readonly property int typeModal: SurfaceCoordinator.Type.Modal
    readonly property int typePanel: SurfaceCoordinator.Type.Panel

    // Ordered list: most-recently-opened last
    property var entries: []

    function register(surface, kind) {
        unregister(surface);
        entries.push({ surface: surface, kind: kind, screen: surface.screen || null });
    }

    function unregister(surface) {
        for (var i = entries.length - 1; i >= 0; i--) {
            if (entries[i].surface === surface) {
                entries.splice(i, 1);
                return;
            }
        }
    }

    function topmostModal() {
        for (var i = entries.length - 1; i >= 0; i--) {
            if (entries[i].kind === SurfaceCoordinator.Type.Modal)
                return entries[i];
        }
        return null;
    }

    function topmostPanel() {
        for (var i = entries.length - 1; i >= 0; i--) {
            if (entries[i].kind === SurfaceCoordinator.Type.Panel)
                return entries[i];
        }
        return null;
    }

    /// Close the topmost Modal, or the last-opened Panel if no Modal.
    function handleEscape() {
        var entry = topmostModal();
        if (!entry) entry = topmostPanel();
        if (!entry) return false;

        var surface = entry.surface;
        // Use surface-level method: close() delegates to lifecycle internally
        if (surface && typeof surface.close === "function") {
            surface.close();
            return true;
        }
        return false;
    }

    /// Close any active Modal, then open the given one.
    function openModal(surface) {
        var current = topmostModal();
        if (current && current.surface !== surface && typeof current.surface.close === "function") {
            current.surface.close();
        }
        if (surface && typeof surface.open === "function") {
            surface.open();
        }
    }

    function isTopmostModal(surface) {
        var entry = topmostModal();
        return entry !== null && entry.surface === surface;
    }
}
