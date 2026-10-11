import QtQuick
import QtQuick.Layouts
import "../../theme" as Theme
import "." as Local

// HealthBody.qml — island dashboard for system health.
//
// This is the only body that reads the NVIDIA GPU, and decision 8 makes that
// conditional: the GPU is polled only while this body is visible, so the dGPU
// can enter its low-power state while the dashboard is closed. `active` is set
// by IslandDashboardBody's Loader and is what gates SystemModel's GPU polling.



ColumnLayout {
    id: root

    property var systemModel: null

    Layout.fillWidth: true
    spacing: Theme.Tokens.scaled(Theme.Tokens.spacingXs)

    // Decision 9: query the discrete GPU only while this body exists. It is
    // loaded by IslandDashboardBody's Loader, so its lifetime IS the dashboard
    // being open — that is the gate, and the dGPU stays asleep otherwise.
    //
    // This used to hang off an `active` property declared
    // `readonly property bool active: true`. A constant emits no change
    // signal, so `onActiveChanged` never ran and the GPU was never polled at
    // all: the dashboard silently showed "GPU n/a" forever.
    Component.onCompleted: {
        if (root.systemModel) {
            root.systemModel.gpuPollingEnabled = true;
            if (typeof root.systemModel.requestGpuPoll === "function")
                root.systemModel.requestGpuPoll();
        }
    }

    Component.onDestruction: if (systemModel) systemModel.gpuPollingEnabled = false

    readonly property bool haveData:
        systemModel && (systemModel.status === "live" || systemModel.status === "stale")

    Local.DashboardSection {
        Layout.fillWidth: true
        headline: root.haveData
            ? "CPU  " + Math.round(root.systemModel.cpuUsage) + "%"
            : "Telemetry unavailable"
        headlineColor: root.haveData ? Theme.Tokens.textPrimary : Theme.Tokens.stateWarning
        details: {
            if (!root.systemModel) return [];
            var rows = [];
            if (root.haveData) {
                rows.push({
                    text: root.systemModel.cpuFreqAvailable
                        ? (root.systemModel.cpuFreq / 1000).toFixed(1) + " GHz"
                        : "Frequency unavailable"
                });
                rows.push({
                    text: root.systemModel.status === "live"
                        ? "Live telemetry · " + root.systemModel.dataSource
                        : "Stale telemetry · " + Math.round(root.systemModel.ageMs / 1000) + "s old · " + root.systemModel.dataSource,
                    color: root.systemModel.status === "live"
                        ? Theme.Tokens.stateSuccess : Theme.Tokens.stateWarning
                });
                if (root.systemModel.loadAvailable) {
                    rows.push({
                        text: "Load  " + root.systemModel.load1.toFixed(2) + " · "
                            + root.systemModel.load5.toFixed(2) + " · "
                            + root.systemModel.load15.toFixed(2)
                    });
                }
                rows.push({
                    text: "Memory  " + (root.systemModel.memUsed / 1048576).toFixed(1) + " / "
                        + (root.systemModel.memTotal / 1048576).toFixed(1) + " GiB"
                        + (root.systemModel.swapAvailable
                            ? "  ·  Swap " + (root.systemModel.swapUsed / 1048576).toFixed(1) + " GiB" : ""),
                    emphasis: true,
                    color: Theme.Tokens.textPrimary
                });
                var cpuTemp = root.systemModel.cpuTempAvailable ? Math.round(root.systemModel.cpuTemp) + "°C" : "—";
                var gpuTemp = root.systemModel.gpuTempAvailable ? Math.round(root.systemModel.gpuTemp) + "°C" : "—";
                rows.push({
                    text: "Thermals  CPU " + cpuTemp + "  ·  GPU " + gpuTemp,
                    emphasis: true,
                    color: root.systemModel.cpuTempAvailable && root.systemModel.cpuTemp >= 85
                        ? Theme.Tokens.stateDanger
                        : root.systemModel.cpuTempAvailable && root.systemModel.cpuTemp >= 75
                            ? Theme.Tokens.stateWarning : Theme.Tokens.textSecondary
                });
            } else {
                rows.push({
                    text: root.systemModel && root.systemModel.status === "pending"
                        ? "Waiting for telemetry" : "No telemetry source",
                    color: Theme.Tokens.textMuted
                });
            }
            return rows;
        }
        footnote: root.haveData
            ? "NVIDIA compute is polled only while this dashboard is open, so the dGPU can sleep."
            : ""
        footnoteWrap: true
    }
}