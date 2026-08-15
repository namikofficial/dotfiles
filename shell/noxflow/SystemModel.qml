// SystemModel — one atomic CPU/GPU/RAM/thermal/root-disk snapshot every 2 seconds.

import QtQml
import Quickshell
import Quickshell.Io
import "SystemSnapshot.js" as Snapshot

QtObject {
    id: root

    property real cpuUsage: 0
    property real cpuTemp: 0
    property real memUsed: 0
    property real memTotal: 0
    property real memPercent: 0
    property real diskUsed: 0
    property real diskTotal: 0
    property real diskPercent: 0
    property real gpuUsage: 0
    property real gpuMemUsed: 0
    property real gpuMemTotal: 0
    property bool gpuAvailable: false
    property string gpuName: ""
    property bool ready: false
    property string lastError: ""

    // Kept for compatibility with existing consumers. It now means that a
    // valid CPU counter baseline exists, rather than that a process returned.
    property bool hasPrev: false
    property real prevIdle: 0
    property real prevTotal: 0
    property bool snapshotApplied: false
    property string processError: ""

    property Timer pollTimer: Timer {
        interval: 2000
        repeat: true
        onTriggered: root.pollAll()
    }

    property Process snapshotProcess: Process {
        id: snapshotProcess
        running: false
        command: ["sh", "-c",
            "set -u; " +
            "set -- $(sed -n '1{s/^cpu[[:space:]]*//;p;q}' /proc/stat); printf 'CPU=%s %s %s %s %s %s %s %s\\n' \"$1\" \"$2\" \"$3\" \"$4\" \"${5:-0}\" \"${6:-0}\" \"${7:-0}\" \"${8:-0}\"; " +
            "awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {if (t>0 && a>=0) printf \"MEM=%.0f %.0f\\n\",t,a; else exit 1}' /proc/meminfo; " +
            "df -Pk / | awk 'NR==2 {printf \"DISK=%.0f %.0f\\n\",$3,$2}'; " +
            "temp=$(awk 'FNR==1 && ($1+0)>m {m=$1+0} END {if (m>0) print m}' /sys/class/thermal/thermal_zone*/temp 2>/dev/null || true); printf 'TEMP=%s\\n' \"${temp:-NA}\"; " +
            "gpu=$(timeout -k 1 1 nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,name --format=csv,noheader,nounits 2>/dev/null | head -1 | sed 's/, */|/g' || true); " +
            "case \"$gpu\" in *'|'*) ;; *) gpu='';; esac; " +
            "if [ -z \"$gpu\" ]; then busy=$(awk 'FNR==1 {print; exit}' /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null || true); [ -n \"$busy\" ] && gpu=\"$busy|0|0|Integrated GPU\"; fi; printf 'GPU=%s\\n' \"${gpu:-NA}\""
        ]
        stdout: StdioCollector {
            onStreamFinished: root.applySnapshot(this.text)
        }
        stderr: StdioCollector {
            onStreamFinished: root.processError = String(this.text || "").trim()
        }
        onExited: function(code) {
            if (code !== 0 && !root.snapshotApplied)
                root.lastError = root.processError || "System snapshot command failed (exit " + code + ")";
            else if (!root.snapshotApplied && root.lastError === "")
                root.lastError = "System snapshot returned no valid data";
        }
    }

    function start() { pollTimer.restart(); pollAll(); }
    function stop() { pollTimer.stop(); }

    function pollAll() {
        if (snapshotProcess.running) return;
        snapshotApplied = false;
        processError = "";
        snapshotProcess.running = true;
    }

    function applySnapshot(text) {
        var parsed = Snapshot.parseSnapshot(text, hasPrev ? {
            cpuUsage: cpuUsage,
            cpuIdle: prevIdle,
            cpuTotal: prevTotal
        } : null);
        if (!parsed.ok) {
            lastError = parsed.error;
            return false;
        }
        cpuUsage = parsed.cpuUsage;
        cpuTemp = parsed.cpuTemp;
        memUsed = parsed.memUsed;
        memTotal = parsed.memTotal;
        memPercent = parsed.memPercent;
        diskUsed = parsed.diskUsed;
        diskTotal = parsed.diskTotal;
        diskPercent = parsed.diskPercent;
        gpuUsage = parsed.gpuUsage;
        gpuMemUsed = parsed.gpuMemUsed;
        gpuMemTotal = parsed.gpuMemTotal;
        gpuAvailable = parsed.gpuAvailable;
        gpuName = parsed.gpuName;
        prevIdle = parsed.cpuIdle;
        prevTotal = parsed.cpuTotal;
        hasPrev = true;
        ready = true;
        lastError = "";
        snapshotApplied = true;
        return true;
    }
}
