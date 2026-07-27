import QtQml
import "ModelUtils.js" as Utils

ProviderModel {
    providerName: "power"
    property string activeProfile: ""
    property var availableProfiles: []
    property bool profilesAvailable: false

    function applySnapshot(snapshot) {
        if (!Utils.applyBase(this, snapshot, providerName)) return false;
        var next = snapshot.data;
        activeProfile = Utils.stringOr(next.active_profile, "");
        availableProfiles = Array.isArray(next.available_profiles) ? next.available_profiles : [];
        profilesAvailable = next.profiles_available === true;
        return true;
    }
}
