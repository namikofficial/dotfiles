import QtQml
import "ModelUtils.js" as Utils

ProviderModel {
    providerName: "power"
    property bool present: false
    property var percentage: null
    property string chargingState: "unknown"
    property var acOnline: null
    property var timeToEmptySeconds: null
    property var timeToFullSeconds: null
    property var healthPercentage: null
    property string warningLevel: "unknown"
    property bool critical: false

    function applySnapshot(snapshot) {
        if (!Utils.applyBase(this, snapshot, providerName)) return false;
        var next = snapshot.data;
        present = next.battery_present === true;
        percentage = Utils.nullableNumber(next.percentage);
        chargingState = Utils.stringOr(next.charging_state, "unknown");
        acOnline = Utils.nullableBool(next.ac_online);
        timeToEmptySeconds = Utils.nullableNumber(next.time_to_empty_seconds);
        timeToFullSeconds = Utils.nullableNumber(next.time_to_full_seconds);
        healthPercentage = Utils.nullableNumber(next.health_percentage);
        warningLevel = Utils.stringOr(next.warning_level, "unknown");
        critical = next.critical === true;
        return true;
    }
}
