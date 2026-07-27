// SystemModel — CPU/GPU/RAM/thermal monitor.
// Polls /proc, nvidia-smi, sensors every 2 seconds.
// Properties: cpuUsage, cpuTemp, memUsed, memTotal, memPercent, gpuUsage, gpuMemUsed, gpuMemTotal

import QtQml
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // ── Properties ──
    property real cpuUsage: 0
    property real cpuTemp: 0
    property real memUsed: 0
    property real memTotal: 0
    property real memPercent: 0
    property real gpuUsage: 0
    property real gpuMemUsed: 0
    property real gpuMemTotal: 0
    property bool gpuAvailable: false
    property string gpuName: ""

    // ── Poll timer (must be property in QtObject) ──
    property Timer pollTimer: Timer {
        id: pollTimer
        interval: 2000
        repeat: true
        onTriggered: root.pollAll()
    }

    function start() { pollTimer.restart(); root.pollAll(); }
    function stop() { pollTimer.stop(); }

    // ── State buffers ──
    property real prevIdle: 0
    property real prevTotal: 0
    property bool hasPrev: false

    function pollAll() {
        pollCpu();
        pollMem();
        pollGpu();
        pollTemp();
    }

    // CPU from /proc/stat
    function pollCpu() {
        var proc = procCpuRead;
        proc.running = true;
    }

    property Process procCpuRead: Process {
        id: procCpuRead
        running: false
        stdout: SplitParser {
            onRead: function(data) {
                root.parseCpu(data);
            }
        }
        command: ["sh", "-c", "head -n 1 /proc/stat"]
    }

    function parseCpu(data) {
        if (!data) return;
        var lines = data.split("\n");
        var cpuLine = "";
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].indexOf("cpu ") === 0) {
                cpuLine = lines[i];
                break;
            }
        }
        if (!cpuLine) return;

        var parts = cpuLine.trim().split(/\s+/);
        if (parts.length < 5) return;

        var user = parseInt(parts[1]) || 0;
        var nice = parseInt(parts[2]) || 0;
        var sys = parseInt(parts[3]) || 0;
        var idle = parseInt(parts[4]) || 0;
        var iowait = parseInt(parts[5]) || 0;
        var irq = parseInt(parts[6]) || 0;
        var softirq = parseInt(parts[7]) || 0;
        var steal = parseInt(parts[8]) || 0;

        var total = user + nice + sys + idle + iowait + irq + softirq + steal;

        if (root.hasPrev) {
            var totalDelta = total - root.prevTotal;
            var idleDelta = idle - root.prevIdle;
            if (totalDelta > 0) {
                root.cpuUsage = Math.round((1 - idleDelta / totalDelta) * 100);
            }
        }

        root.prevTotal = total;
        root.prevIdle = idle;
        root.hasPrev = true;
    }

    // Memory from /proc/meminfo
    property Process procMemRead: Process {
        id: procMemRead
        running: false
        stdout: SplitParser {
            onRead: function(data) {
                root.parseMem(data);
            }
        }
    }

    function pollMem() {
        procMemRead.command = ["sh", "-c", "awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {print t, a}' /proc/meminfo"];
        procMemRead.running = true;
    }

    function parseMem(data) {
        if (!data) return;
        var parts = data.trim().split(/\s+/);
        if (parts.length < 2) return;
        var total = parseFloat(parts[0]) || 0;
        var avail = parseFloat(parts[1]) || 0;
        if (total > 0) {
            root.memTotal = total;
            root.memUsed = total - avail;
            root.memPercent = Math.round(((total - avail) / total) * 100);
        }
    }

    // GPU via nvidia-smi with fallback
    property Process procGpuRead: Process {
        id: procGpuRead
        running: false
        stdout: SplitParser {
            onRead: function(data) {
                root.parseGpu(data);
            }
        }
        onExited: function(code, status) {
            if (code !== 0) {
                root.gpuAvailable = false;
            }
        }
    }

    function pollGpu() {
        procGpuRead.command = ["sh", "-c",
            "nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,name --format=csv,noheader,nounits 2>/dev/null || " +
            "cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -1 || " +
            "echo ''"];
        procGpuRead.running = true;
    }

    function parseGpu(data) {
        if (!data || !data.trim()) {
            root.gpuAvailable = false;
            return;
        }
        data = data.trim();

        // nvidia-smi format: "usage, mem_used, mem_total, name"
        // radeontop format: single number (percentage)
        if (data.indexOf(",") >= 0) {
            var parts = data.split(",");
            if (parts.length >= 3) {
                root.gpuUsage = Math.round(parseFloat(parts[0].trim()) || 0);
                root.gpuMemUsed = Math.round(parseFloat(parts[1].trim()) || 0);
                root.gpuMemTotal = Math.round(parseFloat(parts[2].trim()) || 0);
                root.gpuName = parts.length >= 4 ? parts[3].trim() : "NVIDIA";
                root.gpuAvailable = true;
            }
        } else {
            // AMD fallback — just percentage
            root.gpuUsage = Math.round(parseFloat(data) || 0);
            root.gpuMemUsed = 0;
            root.gpuMemTotal = 0;
            root.gpuName = "AMD";
            root.gpuAvailable = true;
        }
    }

    // Thermal: read CPU temp from thermal zones or sensors
    property Process procTempRead: Process {
        id: procTempRead
        running: false
        stdout: SplitParser {
            onRead: function(data) {
                root.parseTemp(data);
            }
        }
    }

    function pollTemp() {
        procTempRead.command = ["sh", "-c",
            "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -rn | head -1 || " +
            "sensors -j 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(max(int(v.get(\"temp1_input\",0))/1000 for c in d.values() if isinstance(c,dict) for k,v in c.items() if isinstance(v,dict)))' 2>/dev/null || " +
            "echo '0'"];
        procTempRead.running = true;
    }

    function parseTemp(data) {
        if (!data) return;
        var val = parseFloat(data.trim()) || 0;
        // /proc/thermal gives millidegrees
        if (val > 200) val = val / 1000;
        root.cpuTemp = Math.round(val);
    }
}
