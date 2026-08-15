function finiteNumber(value) {
    var number = Number(value);
    return isFinite(number) ? number : NaN;
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
        cpuTemp: 0,
        gpuAvailable: false,
        gpuUsage: 0,
        gpuMemUsed: 0,
        gpuMemTotal: 0,
        gpuName: ""
    };

    var temperature = finiteNumber(fields.TEMP);
    if (!isNaN(temperature) && temperature > 0) {
        result.cpuTemp = Math.round(temperature > 200 ? temperature / 1000 : temperature);
    }

    var gpu = String(fields.GPU || "").split("|");
    if (gpu.length >= 4) {
        var gpuUsage = finiteNumber(gpu[0]);
        var gpuMemUsed = finiteNumber(gpu[1]);
        var gpuMemTotal = finiteNumber(gpu[2]);
        if (!isNaN(gpuUsage) && !isNaN(gpuMemUsed) && !isNaN(gpuMemTotal)) {
            result.gpuAvailable = true;
            result.gpuUsage = Math.round(gpuUsage);
            result.gpuMemUsed = Math.round(gpuMemUsed);
            result.gpuMemTotal = Math.round(gpuMemTotal);
            result.gpuName = gpu.slice(3).join("|").trim();
        }
    }
    return result;
}
