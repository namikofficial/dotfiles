.pragma library

function greetingForHour(hour) {
    var h = Number(hour);
    if (!isFinite(h) || isNaN(h)) return "Hello";
    h = Math.floor(h) % 24;
    if (h < 0) h += 24;
    if (h >= 5 && h < 12) return "Good morning";
    if (h >= 12 && h < 17) return "Good afternoon";
    if (h >= 17 && h < 24) return "Good evening";
    return "Late night";
}

function greetingForDate(date) {
    var d = date instanceof Date ? date : new Date(date);
    if (isNaN(d.getTime())) return greetingForHour(new Date().getHours());
    return greetingForHour(d.getHours());
}
