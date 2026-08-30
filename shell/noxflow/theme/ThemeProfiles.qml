pragma Singleton
import QtQml
import "ThemeProfiles.js" as ProfileData

QtObject {
    id: root

    /// Return a profile object by name (or fallback to expressive).
    function getProfile(name) {
        return ProfileData.getProfile(name);
    }

    /// Return all known profile names.
    function profileNames() {
        return ProfileData.profileNames();
    }

    /// Return the count of available profiles.
    readonly property int count: ProfileData.profileNames().length
}
