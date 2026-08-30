// SystemModel — one atomic CPU/GPU/RAM/thermal/root-disk snapshot every 2 seconds.
//
// Telemetry comes from local /proc, /sys, and nvidia-smi. The model never
// fabricates values: every per-metric field is paired with an `...Available`
// flag that the UI uses to distinguish "no data yet" from "real zero".
//
// Freshness is exposed as a 4-state status:
//   "pending"     no snapshot has ever been applied (startup)
//   "live"        a recent successful snapshot is in scope (age <= staleAfterMs)
//   "stale"       the last snapshot is older than staleAfterMs
//   "unavailable" an attempt failed before any usable snapshot existed
//
// Data source is also exposed so the UI can label telemetry truthfully:
//   "proc"         /proc + /sys only (CPU/RAM/disk/thermal/loadavg/freq/swap)
//   "proc+nvidia"  above + an NVIDIA GPU reported by nvidia-smi
//   "proc+integrated" above + a sysfs GPU (DRM card) — typically the iGPU
//
// The integrated source is identified by its discovered DRM card directory
// (e.g. "card0"); the NVIDIA source is identified by the nvidia-smi GPU
// index (e.g. "0"). Neither is hardcoded anywhere in the parser.

import QtQml
import Quickshell
import Quickshell.Io
import "SystemSnapshot.js" as Snapshot

QtObject {
    id: root

    // ── Core flat metrics (kept for downstream QML consumers) ──
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

    // Extended metrics (preserved from prior edits).
    property real cpuFreq: 0          // MHz average across cores
    property real load1: 0            // 1-minute load average
    property real load5: 0            // 5-minute load average
    property real load15: 0           // 15-minute load average
    property real swapUsed: 0
    property real swapTotal: 0
    property real gpuPower: 0         // watts, NVIDIA only
    property real gpuTemp: 0          // °C, NVIDIA only

    // ── Per-metric availability (paired with the flat metrics above) ──
    property bool cpuTempAvailable: false
    property bool cpuFreqAvailable: false
    property bool loadAvailable: false
    property bool swapAvailable: false
    property bool gpuPowerAvailable: false
    property bool gpuTempAvailable: false

    // ── Freshness + source identity ──
    // `status` is the single source of truth for "is this live?".
    readonly property int staleAfterMs: 10000
    property bool ready: false
    property string status: "pending"
    property real lastUpdateMs: 0
    property real ageMs: 0
    property bool stale: false
    property string dataSource: "proc"
    property string gpuSource: "none"   // none | integrated | nvidia | unknown
    property string gpuSourceId: ""     // DRM card name or NVIDIA index

    property string lastError: ""

    // Kept for compatibility with existing consumers. It now means that a
    // valid CPU counter baseline exists, rather than that a process returned.
    property bool hasPrev: false
    property real prevIdle: 0
    property real prevTotal: 0
    property bool snapshotApplied: false
    property string processError: ""

    // ── Polling ──
    property Timer pollTimer: Timer {
        interval: 2000
        repeat: true
        onTriggered: root.pollAll()
    }

    // ── Per-snapshot Process ──
    // The shell command emits one `KEY=value` per metric. The GPU line layout
    // is busy|memUsed|memTotal|power|temp|name|source|sourceId so that
    // names containing commas round-trip cleanly through awk -F,. The
    // integrated source is identified by its sysfs card directory name
    // (`card0`, `card1`, …) discovered via glob — never hardcoded.
    property Process snapshotProcess: Process {
        id: snapshotProcess
        running: false
        command: ["sh", "-c",
            "set -u; " +
            "set -- $(sed -n '1{s/^cpu[[:space:]]*//;p;q}' /proc/stat); printf 'CPU=%s %s %s %s %s %s %s %s\\n' \"$1\" \"$2\" \"$3\" \"$4\" \"${5:-0}\" \"${6:-0}\" \"${7:-0}\" \"${8:-0}\"; " +
            "awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} /^SwapTotal:/ {s=$2} /^SwapFree:/ {f=$2} END {if (t>0 && a>=0) printf \"MEM=%.0f %.0f\\n\",t,a; if (s>0) printf \"SWAP=%.0f %.0f\\n\",s,f}' /proc/meminfo; " +
            "df -Pk / | awk 'NR==2 {printf \"DISK=%.0f %.0f\\n\",$3,$2}'; " +
            "temp=$(awk 'FNR==1 && ($1+0)>m {m=$1+0} END {if (m>0) print m}' /sys/class/thermal/thermal_zone*/temp 2>/dev/null || true); printf 'TEMP=%s\\n' \"${temp:-NA}\"; " +
            "freq=$(awk '/cpu MHz/ {sum+=$4; c++} END {if(c>0) printf \"%.0f\", sum/c}' /proc/cpuinfo 2>/dev/null || echo 'NA'); printf 'FREQ=%s\\n' \"$freq\"; " +
            "read l1 l5 l15 rest < /proc/loadavg; printf 'LOAD=%s %s %s\\n' \"$l1\" \"$l5\" \"$l15\"; " +
            // One bounded NVIDIA query. The first six CSV fields are fixed;
            // awk rejoins every remaining field as the name, preserving
            // uncommon names containing commas.
            "nvidia=$(timeout -k 1 1 nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,power.draw,temperature.gpu,index,name --format=csv,noheader,nounits 2>/dev/null | head -1 || true); " +
            "if [ -n \"$nvidia\" ]; then " +
              "  gpu=$(printf '%s' \"$nvidia\" | awk -F, '{name=$7; for (i=8; i<=NF; i++) name=name \",\" $i; printf \"%s|%s|%s|%s|%s|%s|nvidia|%s\\n\", $1, $2, $3, $4, $5, name, $6}'); " +
            "else " +
              // Integrated: discover the card directory name from sysfs.
              // This must NOT hardcode card numbers — every value comes from
              // glob expansion at runtime.
              "  card=$(awk 'FNR==1 {n=split(FILENAME, p, \"/\"); c=p[n-2]; print c; exit}' /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null || true); " +
              "  busy=$(awk 'FNR==1 {print; exit}' /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null || true); " +
              "  if [ -n \"$busy\" ]; then " +
              "    gpu=\"$busy|0|0|0|0|Integrated GPU|integrated|${card:-unknown}\"; " +
              "  else " +
              "    gpu=\"\"; " +
              "  fi; " +
            "fi; " +
            "printf 'GPU=%s\\n' \"${gpu:-NA}\""
        ]
        stdout: StdioCollector {
            onStreamFinished: root.applySnapshot(this.text)
        }
        stderr: StdioCollector {
            onStreamFinished: root.processError = String(this.text || "").trim()
        }
        onExited: function(code) {
            if (code !== 0 && !root.snapshotApplied) {
                root.lastError = root.processError || "System snapshot command failed (exit " + code + ")";
                root.markUnavailable();
            } else if (!root.snapshotApplied && root.lastError === "") {
                root.lastError = "System snapshot returned no valid data";
                root.markUnavailable();
            }
        }
    }

    // ── Lifecycle ──
    function start() { pollTimer.restart(); pollAll(); }
    function stop() { pollTimer.stop(); }

    // Drive a 1-Hz freshness tick so `ageMs` and `stale` advance even if
    // polling is paused or blocked. Backed by a single QML Timer rather than
    // computed properties (which would recompute on every binding read).
    property Timer freshnessTimer: Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.recomputeFreshness()
    }

    function pollAll() {
        if (snapshotProcess.running) return;
        snapshotApplied = false;
        processError = "";
        snapshotProcess.running = true;
    }

    // Mark the model as having failed to produce data on the last attempt.
    // Anything that already has a real value is preserved (we don't drop a
    // good reading because a later poll failed), but the freshness status
    // moves to "unavailable" once the snapshot is too old.
    function markUnavailable() {
        status = Snapshot.freshness(Date.now(), lastUpdateMs, staleAfterMs, false);
        recomputeFreshness();
    }

    function recomputeFreshness() {
        var now = Date.now();
        ageMs = lastUpdateMs > 0 ? now - lastUpdateMs : 0;
        stale = lastUpdateMs > 0 && ageMs > staleAfterMs;
        // Status transitions driven purely by time:
        //   live -> stale   once we cross the staleness threshold
        //   stale stays stale until the next successful snapshot
        if (status === "live" && stale) status = "stale";
    }

    function applySnapshot(text) {
        var parsed = Snapshot.parseSnapshot(text, hasPrev ? {
            cpuUsage: cpuUsage,
            cpuIdle: prevIdle,
            cpuTotal: prevTotal
        } : null);
        if (!parsed.ok) {
            lastError = parsed.error;
            markUnavailable();
            return false;
        }

        // ── Core metrics (always refreshed from a successful snapshot) ──
        cpuUsage = parsed.cpuUsage;
        cpuTemp = parsed.cpuTemp.available ? parsed.cpuTemp.value : 0;
        cpuTempAvailable = parsed.cpuTemp.available;
        memUsed = parsed.memUsed;
        memTotal = parsed.memTotal;
        memPercent = parsed.memPercent;
        diskUsed = parsed.diskUsed;
        diskTotal = parsed.diskTotal;
        diskPercent = parsed.diskPercent;

        // ── GPU ──
        // GPU state is re-derived from this cycle's snapshot. A missing GPU
        // line (no nvidia-smi and no sysfs busy_percent) marks the GPU as
        // currently not reportable — the UI must not flash empty values,
        // but it also must not silently retain numbers from a previous
        // successful cycle. Downstream consumers should gate the row on
        // `gpuAvailable` and consult `lastUpdateMs` / `stale` to decide
        // whether to show stale values.
        if (parsed.gpuAvailable) {
            gpuUsage = parsed.gpuUsage;
            gpuMemUsed = parsed.gpuMemUsed;
            gpuMemTotal = parsed.gpuMemTotal;
            gpuAvailable = true;
            gpuName = parsed.gpuName;
            gpuSource = parsed.gpuSource;
            gpuSourceId = parsed.gpuSourceId;
        } else {
            gpuAvailable = false;
            gpuName = "";
            gpuSource = "none";
            gpuSourceId = "";
        }

        // ── Extended metrics: reset to 0 / unavailable every cycle ──
        // The prior implementation used a "non-regressive" guard
        // (`parsed.cpuFreq > 0 || cpuFreq <= 0`) which meant a missing
        // reading kept the previous positive value forever. Resetting every
        // cycle and only setting the value when the parser marks it
        // available makes "stale" and "unavailable" visible to the UI.
        cpuFreq = parsed.cpuFreq.available ? parsed.cpuFreq.value : 0;
        cpuFreqAvailable = parsed.cpuFreq.available;

        load1 = parsed.load1.available ? parsed.load1.value : 0;
        load5 = parsed.load5.available ? parsed.load5.value : 0;
        load15 = parsed.load15.available ? parsed.load15.value : 0;
        loadAvailable = parsed.load1.available && parsed.load5.available && parsed.load15.available;

        swapUsed = parsed.swapUsed.available ? parsed.swapUsed.value : 0;
        swapTotal = parsed.swapTotal.available ? parsed.swapTotal.value : 0;
        swapAvailable = parsed.swapUsed.available && parsed.swapTotal.available;

        gpuPower = parsed.gpuPower.available ? parsed.gpuPower.value : 0;
        gpuPowerAvailable = parsed.gpuPower.available;
        gpuTemp = parsed.gpuTemp.available ? parsed.gpuTemp.value : 0;
        gpuTempAvailable = parsed.gpuTemp.available;

        // ── Source identity ──
        dataSource = gpuAvailable
            ? (gpuSource === "nvidia" ? "proc+nvidia" : (gpuSource === "integrated" ? "proc+integrated" : "proc+unknown-gpu"))
            : "proc";

        // ── Bookkeeping ──
        prevIdle = parsed.cpuIdle;
        prevTotal = parsed.cpuTotal;
        hasPrev = true;
        lastUpdateMs = Date.now();
        ageMs = 0;
        stale = false;
        status = "live";
        ready = true;
        lastError = "";
        snapshotApplied = true;
        processError = "";
        return true;
    }
}
