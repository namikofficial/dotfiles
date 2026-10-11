.pragma library

// SurfaceStack — the modal stack and Escape routing.
//
// Extracted from PanelController so it can be unit-tested without a windowing
// system. It used to live inside a second coordinator, SurfaceCoordinator,
// which tracked the same surfaces as PanelController but could not see it. The
// two therefore disagreed: PanelController closed every other panel when one
// opened, while SurfaceCoordinator's own contract said panels "may coexist with
// each other and with modals", and Escape followed whichever list it was handed.
//
// One stack, one rule: modals stack on top, at most one panel is ever open, and
// Escape always closes the most recently opened thing.

/**
 * Append a surface to the modal stack, removing any earlier entry for the same
 * object so re-registering cannot duplicate it.
 */
function push(stack, surface) {
    if (!surface) return stack;
    var kept = [];
    for (var i = 0; i < stack.length; i++) {
        if (stack[i] !== surface) kept.push(stack[i]);
    }
    kept.push(surface);
    return kept;
}

/**
 * Drop a surface from the modal stack. Called on destruction, when the entry
 * would otherwise keep a dead reference alive.
 */
function remove(stack, surface) {
    if (!surface) return stack;
    var kept = [];
    var changed = false;
    for (var i = 0; i < stack.length; i++) {
        if (stack[i] === surface) { changed = true; continue; }
        kept.push(stack[i]);
    }
    return changed ? kept : stack;
}

/**
 * The modal that should receive input: the last one that still exists.
 *
 * @param isDestroyed predicate identifying a dead surface; a destroyed entry
 *        must be skipped rather than returned, or Escape would call a method
 *        on a deleted QML object and throw.
 */
function topmost(stack, isDestroyed) {
    for (var i = stack.length - 1; i >= 0; i--) {
        if (!isDestroyed(stack[i])) return stack[i];
    }
    return null;
}

/**
 * What an Escape key press should close.
 *
 * A modal always wins over a panel: the modal is on top. Only when nothing is
 * stacked does Escape fall through to the active panel.
 *
 * @returns {{type: string, surface: object}} type is "modal", "panel", or
 *          "none" when nothing should handle the key.
 */
function escapeTarget(stack, activePanel, isDestroyed) {
    var modal = topmost(stack, isDestroyed);
    if (modal) return { type: "modal", surface: modal };
    if (activePanel) return { type: "panel", surface: activePanel };
    return { type: "none", surface: null };
}