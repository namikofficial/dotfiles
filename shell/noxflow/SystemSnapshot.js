// SystemSnapshot.js — parses the SystemModel `sh -c` snapshot stream into a
// structured result. Anything we cannot parse is reported as
// `available: false` for the affected metric rather than as a stale 0.
//
// Output line keys (all emitted by SystemModel.qml):
//   CPU=  <user nice system idle iowait irq softirq steal> (8 fields)
//   MEM=  <totalKb availableKb>
//   SWAP= <totalKb freeKb>            (omitted if no swap)
//   DISK= <usedKb totalKb>
//   TEMP= <milliCelsius | "NA">
//   FREQ= <mhz | "NA">
//   LOAD= <l1 l5 l15>
//   GPU=  <busy|memUsed|memTotal|power|temp|name|source|sourceId>
//
// The GPU line is emitted by SystemModel.qml; the parser only validates shape.
// `name` may contain commas because we re-emit it via awk -F, and is always
// the 6th field. `source` is one of "nvidia" or "integrated". `sourceId` is
// the GPU index reported by nvidia-smi for NVIDIA, or the DRM card directory
// name (e.g. "card0") for integrated. Both are discovered at runtime — no
// hardcoded indexes.
//
// Anything reported as "NA" or unparseable is exposed to the QML side as an
// explicit `available: false` flag rather than as a stale positive value.

function finiteNumber(value) {
    var number = Number(value);
    return isFinite(number) ? number : NaN;
}

function emptyMetric() {
    return {
        available: false,
        value: NaN
    };
}

function classifyFreshness(nowMs, lastUpdateMs, staleAfterMs, succeeded) {
    // Freshness lifecycle:
    //   "pending"     no snapshot has ever been applied
    //   "live"        a recent successful snapshot is in scope
    //   "stale"       a snapshot was applied but is older than `staleAfterMs`
    //   "unavailable" no usable snapshot exists after an attempt failed
    // A failed refresh with a prior snapshot returns "stale" so callers may
    // retain it only with an explicit stale label.
    if (!succeeded && lastUpdateMs === 0) return "unavailable";
    if (!succeeded) return "stale";
    if (nowMs - lastUpdateMs > staleAfterMs) return "stale";
    return "live";
}

// Public helper for tests / external callers. Returns one of:
//   "pending" | "live" | "stale" | "unavailable"
// Caller passes the persisted context (timestamp + last success flag) and
// the configured staleness threshold.
function freshness(nowMs, lastUpdateMs, staleAfterMs, lastSucceeded) {
    return classifyFreshness(nowMs, lastUpdateMs, staleAfterMs,
        lastSucceeded === true);
}

function parseSnapshot(text, previous) {
    var fields = {};
    var lines = String(text || "").trim().split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
        var separator = lines[i].indexOf("=");
        if (separator <= 0) continue;
        fields[lines[i].slice(0, separator)] = lines[i].slice(separator + 1).trim();
    }

    var cpu = String(fields.CPU || "").split(/\s+/).map(finiteNumber);
    var memory = String(fields.MEM || "").split(/\s+/).map(finiteNumber);
    var disk = String(fields.DISK || "").split(/\s+/).map(finiteNumber);
    var swap = String(fields.SWAP || "").split(/\s+/).map(finiteNumber);
    var load = String(fields.LOAD || "").split(/\s+/).map(finiteNumber);
    var freqRaw = fields.FREQ;
    var tempRaw = fields.TEMP;

    if (cpu.length < 8 || cpu.some(isNaN) || memory.length !== 2 || memory.some(isNaN) ||
            disk.length !== 2 || disk.some(isNaN) || memory[0] <= 0 || disk[1] <= 0 ||
            memory[1] < 0 || memory[1] > memory[0] || disk[0] < 0 || disk[0] > disk[1]) {
        return { ok: false, error: "Malformed system snapshot" };
    }

    var idle = cpu[3] + cpu[4];
    var total = cpu.reduce(function(sum, value) { return sum + value; }, 0);
    if (total <= 0) return { ok: false, error: "Invalid CPU counters" };

    var cpuUsage = previous && previous.cpuUsage !== undefined ? previous.cpuUsage : 0;
    if (previous && previous.cpuTotal !== undefined && total > previous.cpuTotal) {
        var idleDelta = idle - previous.cpuIdle;
        cpuUsage = Math.max(0, Math.min(100, Math.round((1 - idleDelta / (total - previous.cpuTotal)) * 100)));
    }

    var result = {
        ok: true,
        cpuUsage: cpuUsage,
        cpuIdle: idle,
        cpuTotal: total,
        memTotal: memory[0],
        memUsed: memory[0] - memory[1],
        memPercent: Math.round((memory[0] - memory[1]) / memory[0] * 100),
        diskUsed: disk[0],
        diskTotal: disk[1],
        diskPercent: Math.round(disk[0] / disk[1] * 100),
        cpuTemp: emptyMetric(),
        gpuAvailable: false,
        gpuUsage: 0,
        gpuMemUsed: 0,
        gpuMemTotal: 0,
        gpuName: "",
        gpuSource: "none",
        gpuSourceId: "",
        cpuFreq: emptyMetric(),
        load1: emptyMetric(),
        load5: emptyMetric(),
        load15: emptyMetric(),
        swapUsed: emptyMetric(),
        swapTotal: emptyMetric(),
        gpuPower: emptyMetric(),
        gpuTemp: emptyMetric()
    };

    // CPU temperature. Treat "NA", 0, and unparseable identically.
    if (tempRaw !== undefined && tempRaw !== "NA" && tempRaw !== "") {
        var temperature = finiteNumber(tempRaw);
        if (!isNaN(temperature) && temperature > 0) {
            var tempC = Math.round(temperature > 200 ? temperature / 1000 : temperature);
            result.cpuTemp = { available: true, value: tempC };
        }
    }

    // CPU frequency (MHz).
    if (freqRaw !== undefined && freqRaw !== "NA" && freqRaw !== "") {
        var freq = finiteNumber(freqRaw);
        if (!isNaN(freq) && freq > 0) {
            result.cpuFreq = { available: true, value: Math.round(freq) };
        }
    }

    // Load averages (1, 5, 15 min). All three must be numeric and finite.
    if (load.length >= 3 && !load.some(isNaN)) {
        result.load1 = { available: true, value: parseFloat(load[0].toFixed(2)) };
        result.load5 = { available: true, value: parseFloat(load[1].toFixed(2)) };
        result.load15 = { available: true, value: parseFloat(load[2].toFixed(2)) };
    }

    // Swap. Memory present without swap is reported as unavailable, not zero.
    if (swap.length === 2 && !swap.some(isNaN) && swap[0] >= 0 && swap[1] >= 0) {
        result.swapTotal = { available: true, value: swap[0] };
        result.swapUsed = { available: true, value: Math.max(0, swap[0] - swap[1]) };
    }

    // GPU: 8 fields = busy|memUsed|memTotal|power|temp|name|source|sourceId.
    // Source is "nvidia" or "integrated" so the UI never confuses the
    // compositor iGPU with a discrete GPU.
    var gpu = String(fields.GPU || "").split("|");
    if (gpu.length >= 8) {
        var gpuUsage = finiteNumber(gpu[0]);
        var gpuMemUsed = finiteNumber(gpu[1]);
        var gpuMemTotal = finiteNumber(gpu[2]);
        var gpuName = gpu.slice(5, gpu.length - 2).join("|").trim();
        var gpuSource = String(gpu[gpu.length - 2] || "").trim();
        var gpuSourceId = String(gpu[gpu.length - 1] || "").trim();
        if (!isNaN(gpuUsage) && !isNaN(gpuMemUsed) && !isNaN(gpuMemTotal)) {
            result.gpuAvailable = true;
            result.gpuUsage = Math.round(gpuUsage);
            result.gpuMemUsed = Math.round(gpuMemUsed);
            result.gpuMemTotal = Math.round(gpuMemTotal);
            result.gpuName = gpuName;
            result.gpuSource = (gpuSource === "nvidia" || gpuSource === "integrated") ? gpuSource : "unknown";
            result.gpuSourceId = gpuSourceId;

            // Power (watts) at index 3, temp (°C) at index 4. Missing or 0 is
            // reported as unavailable — never as a stale positive.
            if (gpu.length >= 5) {
                var gpuPowerRaw = finiteNumber(gpu[3]);
                if (!isNaN(gpuPowerRaw) && gpuPowerRaw > 0) {
                    result.gpuPower = { available: true, value: parseFloat(gpuPowerRaw.toFixed(1)) };
                }
            }
            if (gpu.length >= 6) {
                var gpuTempRaw = finiteNumber(gpu[4]);
                if (!isNaN(gpuTempRaw) && gpuTempRaw > 0) {
                    result.gpuTemp = { available: true, value: Math.round(gpuTempRaw) };
                }
            }
        }
    }
    return result;
}
