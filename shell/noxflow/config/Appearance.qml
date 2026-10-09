// Appearance.qml — the single place that applies a settings map to Tokens.
//
// Both the Settings panel (after hydration) and shell.qml (at boot, so a
// theme survives a restart) call this. Previously the panel owned the mapping,
// so a persisted theme only appeared once the panel had been opened.

pragma Singleton
import QtQml
import "../theme" as Theme

QtObject {
    id: root

    /// Apply every appearance key present in `map` to the live tokens.
    /// Returns the list of keys that were actually applied.
    function applyFromMap(map) {
        var applied = [];
        if (!map) return applied;

        if (map["appearance.profile"] !== undefined) {
            var profile = String(map["appearance.profile"]);
            if (Theme.Tokens.currentProfile !== profile) {
                Theme.Tokens.applyProfile(profile);
                applied.push("appearance.profile");
            }
        }
        if (map["appearance.density"] !== undefined) {
            var density = String(map["appearance.density"]);
            if (Theme.Tokens.activeDensity !== density) {
                Theme.Tokens.activeDensity = density;
                applied.push("appearance.density");
            }
        }
        if (map["shell.reduced_motion"] !== undefined) {
            var reduced = !!map["shell.reduced_motion"];
            if (Theme.Tokens.reducedMotion !== reduced) {
                Theme.Tokens.reducedMotion = reduced;
                applied.push("shell.reduced_motion");
            }
        }
        if (map["appearance.radius"] !== undefined) {
            var radius = Number(map["appearance.radius"]);
            if (!isNaN(radius)) {
                Theme.Tokens.applyRadius(radius);
                applied.push("appearance.radius");
            }
        }
        return applied;
    }

    /// Current live values, used as the revert baseline when a daemon write is
    /// rejected.
    function currentValue(key) {
        switch (key) {
            case "appearance.profile": return String(Theme.Tokens.currentProfile);
            case "appearance.density": return String(Theme.Tokens.activeDensity);
            case "shell.reduced_motion": return !!Theme.Tokens.reducedMotion;
            case "appearance.radius": return Number(Theme.Tokens.appearanceRadius);
            default: return undefined;
        }
    }

    /// Restore a previously captured value after a rejected write.
    function revert(key, value) {
        switch (key) {
            case "appearance.profile":
                if (Theme.Tokens.currentProfile !== value) Theme.Tokens.applyProfile(String(value));
                break;
            case "appearance.density":
                if (Theme.Tokens.activeDensity !== value) Theme.Tokens.activeDensity = String(value);
                break;
            case "shell.reduced_motion":
                if (Theme.Tokens.reducedMotion !== value) Theme.Tokens.reducedMotion = !!value;
                break;
            case "appearance.radius":
                Theme.Tokens.applyRadius(Number(value));
                break;
        }
    }
}