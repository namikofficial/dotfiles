.pragma library

var REJECTED_NAME = /(^|[^a-z])(anime|waifu|manga|hentai|kawaii|girl|girls|woman|women|character|avatar|hollow[ -]?knight|game[-_ ]?art|fanart|illustration)([^a-z]|$)/i;

function argumentsFor(roots) {
    var paths = [];
    if (Array.isArray(roots)) {
        for (var i = 0; i < roots.length; i++) {
            var root = String(roots[i] || "").trim();
            if (root && paths.indexOf(root) < 0) paths.push(root);
        }
    }
    if (paths.length === 0) return [];
    return ["find", "--"].concat(paths, [
        "-maxdepth", "1", "-type", "f", "(",
        "-iname", "*.png", "-o", "-iname", "*.jpg", "-o",
        "-iname", "*.jpeg", "-o", "-iname", "*.webp", ")", "-print0"
    ]);
}

function result(exitCode, output) {
    if (exitCode !== 0) return { walls: [], error: "wallpaper scan failed" };

    var paths = String(output || "").split("\u0000");
    var seen = [];
    var walls = [];
    for (var i = 0; i < paths.length; i++) {
        var path = paths[i];
        if (!path || seen.indexOf(path) >= 0) continue;
        seen.push(path);
        var parts = path.split("/");
        var name = parts[parts.length - 1];
        if (REJECTED_NAME.test(name)) continue;
        walls.push({ path: path, name: name });
    }
    walls.sort(function(a, b) { return a.name.localeCompare(b.name); });
    return { walls: walls, error: "" };
}

